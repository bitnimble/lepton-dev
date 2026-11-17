# lepton-dev

Headless dev loop for [Lepton x86_64](https://github.com/pjohno/lepton-x86_64) (community x86_64 port of
Valve's Lepton, Android 14 in podman) on the docker host, without a GPU or Steam, and the Steam Deck bundle it
produces: Lepton with Google Play services, ARM64 translation and [Padmap](addon/padmap/README.md) for gamepad
touch mapping ([deck/README.md](deck/README.md)).

## Layout

| Path | Contents |
| --- | --- |
| `runner/` | Files that run **inside** `lepton-runner`: image (`Containerfile`), env, launch/sysbake/stage/bundle scripts |
| `bin/` | Host-side helpers (run from this dev container via the docker socket) |
| `host/` | Scripts run as **root on the docker host** (via privileged `nsenter`); see Host changes |
| `addon/` | The Lepton + Padmap add-on, shipped as a bundle's `compat_tool/lepton-padmap/`; `addon/padmap/` is Padmap's APK, start script and layouts, vendored by `bin/update-padmap.sh` from [bitnimble/padmap](https://github.com/bitnimble/padmap) (checked out next to this repo) |
| `deck/` | Deck-side installer/updater, bundle builder, the Lepton Game Manager binary (`lepton-manager`) and user guide; the Deck runs them from a clone of this repo |
| `manager/` | The Lepton Game Manager (Rust, egui): adds and manages Lepton games in Steam, from Desktop or Gaming Mode |
| `bundle/` (gitignored) | On the Deck: Android bundles built by `deck/build-bundle.sh` or copied from `data/deck-dist/<id>/` |
| `patches/` | Patched release files that `patches/apply.sh` installs into a `compat_tool/` (runner stages via `bin/push.sh`, the runner's Deck bundle, the Deck via `deck/install.sh`): `liblepton.sh`, `properties.sh`, `lepton-x86_64-entry` and the NDK compatibility shim (`ndk_auxv.c`, built to `liblepton_ndk_auxv.so` by `bin/build-ndk-shim.sh`); the `*.patch` files document the `liblepton.sh` and entry changes |
| `diag/` | Hang-triage probes for a running session |
| `docs/screens/` | Reference screenshots |
| `data/` (gitignored) | Release bundle, Google r14 system image, APK/APKM files, sysbox sources/builds, screenshots |

## Architecture

```
docker host (Debian 13, xanmod 6.18, binder_linux loaded)
└─ lepton-runner  (docker, runtime sysbox-runc: root inside = host uid 165536)
   ├─ systemd, Fedora 44, podman (rootful), headless weston (socket gamescope-0)
   └─ lepton-<context>  (podman, Lepton's own command line, Android 14 /init)
```

Lepton normally runs rootless podman. Inside sysbox that fails: nested-user-namespace `proc`/overlay mounts
come back EINVAL/EPERM because sysbox-fs's nsenter agent joins the requester's child user namespace before
its ancestor-owned IPC namespace. Running podman as the runner's root avoids the nested user namespace;
the runner's root is still unprivileged on the host. `patches/rootful-liblepton.patch` adapts Lepton:

- root: `--user 0:0` instead of `--userns=keep-id…`, plus `--device-cgroup-rule='c *:* rwm'` (binderfs
  nodes get a dynamic char major missing from rootful podman's device allowlist);
- `as_container_owner` instead of `podman unshare` (rootless-only).

Runner-level requirements (`bin/start-runner.sh`, `runner/Containerfile`, the patched `liblepton.sh` and the
`host/` scripts named below):

- `--device-cgroup-rule "c <binder major>:* rwm"` on the runner itself (major read from `/proc/devices`);
- `seccomp=unconfined`: docker's default profile denies `mount` (it gates on CAP_SYS_ADMIN from docker's
  cap list, and its ERRNO outranks sysbox's notify filter);
- a volume at `/var/lib/containers`: overlay upperdirs cannot live on the runner's own overlay root;
- journald `ReadKMsg=no`, setuid `newuidmap`, rshared `/`, podman `default_sysctls = []`,
  `cgroup_manager = "cgroupfs"` (CI-style `/sys/fs/cgroup/lepton-<ctx>` dirs);
- `LEPTON_ADB=/usr/bin/adb` (Fedora `android-tools`), `LEPTON_FORCE_SOFTWARE=true` (image ships AMD drivers only);
- `/dev/dma_heap/system`, owned on the host by uid 165536 (the runner's root; `host/host-dma-heap.sh`):
  Lepton only enables Codec2 (`debug.stagefright.ccodec=4`) when it can open the heap, and without Codec2
  Android has no video encoder;
- a PulseAudio socket for Android's audio HAL: `ensure_audio` runs PipeWire + WirePlumber + `pipewire-pulse`
  as root with a null sink (`runner/pipewire-null-sink.conf`). Without it AudioFlinger blocks 4s per write;
- `/dev/uinput` (owned by uid 165536, `host/host-uinput.sh`), the host's `/dev/input` (read-only) and
  `--device-cgroup-rule "c 13:* rwm"`, for the virtual test pad (`runner/vpad.c`, unit `lepton-vpad`). Sysbox
  serves `/sys/devices/virtual` itself with empty attributes for virtual input devices and refuses a docker
  bind there, so the host's `/sys/devices/virtual/input` is mounted at `/run/host-virtual-input` and
  bind-mounted over it after start; Lepton's gamepad passthrough reads those attributes.

`docker cp` into sysbox containers is unreliable; scripts stream files over `docker exec -i … cat`.

## Stages (inside the runner, `/var/lib/containers/lepton`)

| Stage | Made by | Contents |
| --- | --- | --- |
| `stage` | `runner/setup-rootful.sh` | v0.2.0-alpha release bundle, root-owned |
| `ndk` | `runner/ndk-stage.sh` + `runner/sysbake-rootful.sh` | + Google NDK translation (ARM64) |
| `gapps` | `runner/gapps-stage.sh` + `runner/sysbake-rootful.sh` | + NDK + GMS/GSF/Play Store |

Stages come from `lepton-customize` (run as `dev`; it refuses root) using Google's
`system-images;android-34;google_apis_playstore;x86_64` r14 zip (SHA-1 `01d32617…`). The bundled isolated
sysbake helper is rootless-only, so sysbake uses Lepton's own `lepton sysbake` (`LEPTON_ALLOW_LOCAL_SYSBAKE=1`).

## Dev loop

```bash
bin/start-runner.sh                      # (re)create runner; volumes keep stages and profiles
bin/push-inputs.sh                       # stream data/ inputs into the runner
bin/push.sh                              # runner scripts, add-on and patches/ into every stage
bin/build-ndk-shim.sh                    # rebuild patches/liblepton_ndk_auxv.so from patches/ndk_auxv.c
bin/build-manager.sh [--test]            # build manager/ into deck/lepton-manager (or run its tests + clippy)
bin/launch.sh /var/lib/containers/lepton/run/app.apk 30          # fresh `lepton start app.apk`, detached
bin/status.sh <ctx>; bin/lepton-lines.sh <ctx>; bin/diag.sh <ctx> <package>
bin/shot.sh <ctx> <name>; bin/tap.sh <ctx> <name> x y [x y…]      # 150ms presses: Unity drops short taps
bin/burst.sh <ctx> <name> [count] [seconds]                        # screenshot series
diag/thread-cpu.sh, diag/thread-waits.sh, diag/net-rate.sh, diag/sockets.sh                # hang triage
bin/pad.sh press a | stick l 20000 0 | trigger r 255                # virtual Steam-Input-style pad
bin/lepton-padmap.sh install|edit [ctx] | report                    # add-on CLI, run in the runner
bin/update-padmap.sh                                                # build ../padmap, vendor it into addon/padmap/
bin/build-deck-bundle.sh [id]                                       # Steam Deck bundle -> data/deck-dist/<id>/
```

### Browser remote control

`http://<docker host>:3459/` serves [ws-scrcpy](https://github.com/NetrisTV/ws-scrcpy) from the runner
(`ws-scrcpy.service`, `runner/ws-scrcpy.sh`; built once into the volume by `runner/ws-scrcpy-setup.sh`).
It keeps adb connected to every running session; pick the device, then **Broadway.js** (WebCodecs needs
HTTPS). Video, touch, keyboard and the nav buttons all go through the one HTTP port ("proxy over adb").
Phone browsers get real multi-touch: each browser touch point becomes its own Android pointer (two
simultaneous CDP touches showed as `P: 2/2` with `settings put system pointer_location 1`).
`runner/ws-scrcpy-lepton.patch` adds an **Edit controls** toolbar button (gamepad icon; server route
`POST /lepton/launch?udid=…&app=padmap` opens Padmap's layout editor over the game), keeps fit-to-screen encode bounds landscape, so a portrait phone still gets a landscape-sized
stream, and makes the keyboard toggle work on phones: it focuses an off-screen field (opening the on-screen
keyboard) whose edits are diffed and forwarded as text injection + `DEL`/`ENTER` keys; physical keys still go
through scrcpy key events. Text injection is limited to characters Android's key map can type (ASCII). Encoder Surface input needs `debug.stagefright.c2inputsurface=-1` (`patches/properties.sh`).

`.apkm` bundles need a Steam-style launch (`bin/steamlaunch.sh <appid> <file.apkm> [wait]`, which runs
`runner/run-steamlaunch-rootful.sh`; context `steamlaunch-<appid>`, verb `waitforexitandrun -- <path>`). It goes
through the stage's Steam entry (`compat_tool/lepton-x86_64-entry`, with `LEPTON_NO_BRIDGE=true` in place of the
Deck's Gamescope bridge), so the add-on's session hook runs exactly as on a Deck; its logs land in the runner's
`/var/lib/containers/lepton/home/lepton-logs/latest/`. A session's container IP is shown by `lepton ps`; its adbd
(TCP 5555, `ro.adb.secure=0`) accepts `adb connect` from the runner.

Android boots in ~20s with software rendering. Lepton refuses an existing profile whose runtime fingerprint
(rootfs + sysbake) differs, so switching a game to another stage needs a new app id or a reset.

### Play-installed games (no apk file)

A Play slot is a placeholder `.apkm` (a text file starting with `lepton-play-slot`) that Steam launches like any
game; its profile (one compatdata per appid) holds a game installed from the Play Store, launched by the package
name in `<compatdata>/lepton-launch-package`. `addon/lepton-play.sh`, sourced at the end of the patched
`liblepton.sh`, wraps the app-id, install, launch and teardown functions for slots only:

- nothing recorded, `LEPTON_PLAY_ONLY=true` or a Google sign-in launch: boot to the Play Store; when the session
  stops (Lepton's teardown, while Android is still up), the newest installed app becomes the slot's game;
- `LEPTON_LAUNCH_PACKAGE=<pkg>`: launch and record that package.

A `lepton-open-play-store` file in any game's compatdata makes its next launch a Google sign-in launch (the file is
removed); the Game Manager writes it.

`bin/steamlaunch.sh <appid>` with no game file launches the appid as a slot (`/var/lib/containers/lepton/play-slots/<appid>.apkm`); a
relaunch stops the previous session with SIGTERM first, so its teardown runs.

### Lepton Game Manager (`manager/`)

One controller-first app replaces the Deck's desktop icons and Lepton's per-tool Google wizards. It reads Steam's
files (`userdata/<user>/config/shortcuts.vdf`, `config/config.vdf`'s `CompatToolMapping`,
`compatibilitytools.d/`) and changes the library through Steam's own client API (`SteamClient.Apps.AddShortcut`,
`SetShortcutName`, `SpecifyCompatTool`, `SetCustomArtworkForApp`, `SetShortcutIcon`, `RemoveShortcut`, `RunGame`),
evaluated in Steam's `SharedJSContext` over the Chrome DevTools protocol on 127.0.0.1:8080, so Steam keeps
running. Steam opens that port when `~/.local/share/Steam/.cef-enable-remote-debugging` exists at its start
(`deck/install.sh` creates it). Lepton-side state is the compatdata files above; installed packages come from the
profile's `baked/data_overlay/app/` through `podman unshare`. The gamepad (gilrs) drives egui's own keyboard focus
navigation: D-pad and left stick move focus, A is Enter, B is Escape. `bin/build-manager.sh` builds in a Debian 12
container (glibc 2.36, so the binary runs on any SteamOS 3) and vendors it as `deck/lepton-manager`; its tests
cover the VDF parsers, Steam/Lepton files, the DevTools round trip against a fake Steam and the UI navigation
(egui_kittest).

## Status

| Item | State |
| --- | --- |
| Fossify Calculator (x86_64) | Runs; injected taps work (`docs/screens/calculator-input.png`) |
| AAAAXY 1.8.34 arm64-only | Renders in-game via `libndk_translation` (`docs/screens/aaaaxy-arm64.png`) |
| Pokémon UNITE 1.25.1.1 (`jp.pokemon.pokemonunite`) | Guest account, onboarding, lobby with 3D models (`docs/screens/unite-lobby.png`) on `gapps` (appid 900002, light translator mode); bot match returns to the challenge screen after VS |
| Padmap in UNITE | Pad taps press UNITE's buttons (Start reached the VS screen); joystick and aim drags land at their anchors and follow the sticks, two at once (`docs/screens/padmap-drag.png`, `pointer_location`); the editor opens with Select + Start, binds by pad press and saves (`docs/screens/padmap-editor.png`) |
| UNITE frame rate (software rendering, SurfaceFlinger `--timestats`) | ~25.5 fps on the challenge screen, ~23 fps on the 3D VS screen |
| Steam Deck bundle (`padmap-20261116`) | Packaged and validated by `lepton-customize`; not yet run on a Deck |

## Known issues

- The API 34 r14 translator's heavy optimizer (tiered and heavy-optimize modes) loops forever in
  `HeavyOptimizeRegion → ResolveJumps → SplitBasicBlock` on a region where one jump targets an ARM64 `NOP` and
  another the instruction after it (in UNITE, a comparator in `libMSDKCore.so` at `0x24cd40`; gdb: `r14` in the
  `HeavyOptimizeRegion(unsigned long)` frame is the guest PC), hanging the game at "Loading...". A `NOP` emits no
  code, so both addresses share one branch-target position; after the split for the later one,
  `UpdateBranchTargetsAfterSplit` only walks forward, leaving the `NOP`'s entry on the old block with an iterator
  into the new one, and the next split walks that foreign list forever. The same code is in AOSP's Berberis
  (`heavy_optimizer/riscv64/frontend.cc`). `addon/ndk-translation/fix.py` writes a fixed copy of the translator
  to the tool's `images/rootfs_overlay/` (the walk also moves earlier entries sharing the position; it replaces
  the out-of-line function and the copy inlined into `ResolveJumps`, sources in `addon/ndk-translation/*.S`,
  checked by `test/ndk_translation_fix_test.py`). Lepton bind-mounts the overlay over the rootfs, while its NDK
  shim's checksum still sees the original; no game file changes. UNITE then runs tiered with stock libraries.
- UNITE in the runner sometimes dies within a minute of starting: an ART `ThreadList::Register` SIGSEGV via the
  translator's `AttachCurrentThread` trampoline ("Cannot process signal 11"), after ~1700 threads; the runner's
  UNITE shows "Offline Mode", so its network SDK is likely retrying in a loop.
- Apps cannot create `Android/{data,obb}/<pkg>/…` dirs (e.g. `getExternalCacheDir()`): the app's own mkdir
  hits root-owned dirs, and the `StorageManagerService.mkdirs` fallback canonicalises
  `/storage/emulated/0` through Lepton's `/data/media/0` symlink to the compatdata path, then rejects it
  ("Invalid mkdirs path"). Creating the dir runner-side (`external/Android/data/<pkg>/cache`, mode 2700) works.
- UNITE bot matches show the VS screen, then return to the challenge screen; no new sockets are opened.
  Unconfirmed: incomplete asset download, or ACE anti-cheat (`libanogs`) refusing the environment.
- Lepton ends the session when the game's process dies, and Android may kill a backgrounded game on a
  configuration change (`am_kill … resetConfig`, e.g. after `wm size`/rotation changes). Padmap's editor is an
  overlay window, so the game stays in front.
- A launch can end within a minute of boot when the Play Store finishes updating Google Play services in the
  background: Android force-stops `com.google.android.gms` ("pkg removed") and SIGKILLs apps using it, the game
  included, and Lepton ends the session. The next launch runs on the updated services.
- Lepton's `cmd` wrapper (`/system/bin/cmd`, so also `pm` and `adb install`) treats every install as the game
  and moves the game's installed dir into `/data/steam_app`. That leaves overlay whiteouts over the game's
  `baked/app_overlay/*.apk` and `lib/`; the running game survives on open files, but the next launch fails
  validation ("installed codePath or app_overlay/base.apk missing"). Install other apps with `cmd_real`
  (as `addon/lepton-padmap` does). Repair: replace the whiteouts with the files from
  `lepton-apkm/<hash>/` and re-extract `lib/arm64` from the arm64 split.
- A portrait-only app opened over a landscape game rotates the whole display; Unity then loses its surface.
- Child processes of a translated (arm64) app fail to link: its `su`/`sh` spawns log `CANNOT LINK
  EXECUTABLE "sh": cannot locate symbol "__android_log_write" referenced by "/system/lib64/liblepton_ndk_auxv.so"`.
- SurfaceFlinger `--latency` has no data (no present fences); `--timestats` gives per-layer FPS.
- Toybox `grep -E` with alternations segfaults inside Android; grep logcat on the runner side (`bin/diag.sh`).

## Add-on (`addon/`, shipped as `compat_tool/lepton-padmap/`)

The patched Steam entry (`patches/entry-hook.patch`) sources `entry-hook.sh` on `waitforexitandrun`, so it
runs for Steam launches and for Lepton's "Add Google game" steps alike. Per launch it makes
`~/lepton-logs/<appid>-<date>-<time>/` (`latest` symlink, last 20 kept), tees the entry's output into
`lepton.log`, writes the fixed translator into the overlay (`ndk-translation/fix.py`, see Known issues), puts a copy of `/usr/bin/gamescope` without file capabilities (`~/.cache/lepton-padmap/bin/`) first on `PATH`, and
starts `lepton-padmap session` detached. The copy is for Steam's performance overlay: `mangoapp` reads the game
window's `/proc/<pid>/fdinfo`, which for Lepton's nested gamescope with SteamOS's `cap_sys_nice` is unreadable, and
it aborts on that in a loop (each core dump freezes the game for about a second) until systemd stops restarting it. The session waits for boot, streams `logcat -b all` to `logcat-NNN` (32 MB parts, newest four kept),
installs Padmap with `cmd_real`, reconciles the host's layouts (`~/.config/padmap/layouts/`, seeded from
`addon/padmap/layouts/`) with Android's `/sdcard/Padmap/` (the newer copy of each wins), then every 5s
(re)starts Padmap's daemon as root (Padmap's own `start.sh`, with adbd's environment; 5 failed starts max),
syncs layouts both ways (editor saves go to the host, host edits to the game) and copies new
tombstones/ANRs/dropbox entries out of the profile; a last sync runs when the game ends. All of it is logged in
`session.log`. `lepton-padmap report` tars the last 5 sessions, Lepton's logcats, the layouts, the kernel and
user-session journals (the latter filtered to Steam, gamescope, Lepton and core dumps) and system details to
`~/Desktop/lepton-report-<date>.tar.gz`. `LEPTON_PADMAP=0` in a game's launch options skips Padmap (the
session still collects logs and the gamescope copy still applies).

Padmap reads the pad from evdev inside Android: Lepton's gamepad passthrough binds Steam Input's virtual pads
(`Microsoft X-Box 360 pad N`, 28de:11ff) present at launch, which is what a Deck provides; here
`bin/steamlaunch.sh` starts the matching virtual pad first. How Padmap maps and injects is in its
[README](addon/padmap/README.md#how-it-works).

## Steam Deck bundle

The bundle holds Google components, so it is never distributed: each Deck builds its own with
`deck/build-bundle.sh`, which `deck/install.sh` runs when nothing (or an older auto-built bundle) is installed. It
downloads the pinned inputs in `deck/bundle.env` from their official sources (Lepton's signed GitHub release,
Google's API 34 r14 Play system image from dl.google.com), checks their pinned checksums, then runs Lepton's own
`lepton-customize` rootlessly: base stage, `inject --with-ndk --with-gapps`, `sysbake --rendering amd` (with
`deck/weston-via-gamescope` standing in for Weston when it isn't installed) and `package` as tool id
`lepton_padmap`, into `bundle/`. Bump `BUNDLE_ID` with any input or recipe change; Decks rebuild on their next
Update.

`bin/build-deck-bundle.sh [id]` builds the same bundle in the runner into `data/deck-dist/<id>/` (Lepton's
`.tar.gz`, `.sha256`, `.install.sh`), for testing on your own Deck by copying it into `bundle/` (a bundle there
wins over building). In the runner (`runner/build-deck-bundle.sh`, about 70s) it copies the `gapps` stage,
applies `patches/apply.sh`, sysbakes rootfully, then records that sysbake through `lepton-customize`'s own
validation (`runner/deck-record-sysbake.py` swaps only the rootless helper for the prebuilt result) and packages
with `lepton-customize package`.

On the Deck, `deck/update.sh` pulls, and `deck/install.sh` runs Lepton's own installer when the bundle differs
from the installed one (`--replace`) and deletes the consumed bundle files, then replaces the installed tool's
add-on with `addon/` and applies `patches/apply.sh` (the packager only keeps Lepton's own files, so the add-on
always comes from the checkout). Lepton's runtime fingerprint covers only the rootfs, `services.jar` and the
sysbaked `packages.xml`, so add-on changes (Padmap included) ship by `git pull` alone; Android-side changes
(stage, sysbake) need a new bundle.

## Host changes (docker host, root)

Every root command was reviewed first by a no-context subagent for impact on the host and other containers.

- `binder_linux` loaded (kernel marks it `[permanent]`), `/etc/modules-load.d/binder.conf`.
- `/dev/dma_heap/system` owned by uid 165536 (mode 0600 kept), persisted by
  `/etc/udev/rules.d/70-lepton-dma-heap.rules` (`host/host-dma-heap.sh`). Any future sysbox container shares
  that uid mapping and so gets the heap too; system-heap allocations are not charged to the runner's memory
  cgroup.
- `uinput` loaded (`/etc/modules-load.d/lepton-uinput.conf`), `/dev/uinput` owned by uid 165536 (mode 0600
  kept), and event nodes of virtual (uinput) devices with ids 28de:11ff owned by 165536 too, both via
  `/etc/udev/rules.d/70-lepton-uinput.rules` (`host/host-uinput.sh`). Whoever
  opens `/dev/uinput` can create virtual input devices on the host, including a keyboard that reaches the
  console (Ctrl+Alt+Del, SysRq); this host is headless.
- Sysbox 0.7.1 installed manually (`host/host-stage-sysbox.sh`, `host/host-install-sysbox.sh`), skipping the
  `.deb` postinst (it would add `bip: 172.20.0.1/16`, clashing with the `172.17.0.0/12` pool): binaries in
  `/usr/bin`, units in `/etc/systemd/system`, `sysbox` user + subids `231072:1048576`,
  `/etc/sysctl.d/99-sysbox.conf`, `daemon.json` runtime `sysbox-runc` (backup `daemon.json.bak-pre-sysbox`,
  applied by SIGHUP; `live-restore` is on).
- `/usr/bin/sysbox-fs` replaced by a static build of nestybox/sysbox-fs master `201ec13`
  (`host/Dockerfile.sysbox-fs`, `host/host-swap-sysbox-fs.sh`); original at `/usr/bin/sysbox-fs.0.7.1`.
