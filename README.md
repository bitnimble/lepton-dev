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
| `host/` | Scripts that ran as **root on the docker host** (via privileged `nsenter`); see Host changes |
| `addon/` | The Lepton + Padmap add-on, shipped as a bundle's `compat_tool/lepton-padmap/`; `addon/padmap/` is Padmap's APK, start script and layouts, vendored by `bin/update-padmap.sh` from [bitnimble/padmap](https://github.com/bitnimble/padmap) (checked out next to this repo) |
| `deck/` | Deck-side installer/updater and user guide; the Deck runs them from a clone of this repo |
| `bundle/` (gitignored) | On the Deck: Android bundles copied from `data/deck-dist/<id>/` |
| `patches/` | Patches to the release's `compat_tool/` (`*.patch`), with the patched `liblepton.sh`, `properties.sh` and `lepton-x86_64-entry` that `bin/push.sh` installs |
| `diag/` | Probes used while debugging sysbox/podman/binder |
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

Runner-level requirements (all in `bin/start-runner.sh` and `runner/Containerfile`):

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
bin/push.sh                              # runner scripts + patched liblepton into every stage
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
through scrcpy key events. Text injection is limited to characters Android's key map can type (ASCII). Encoder Surface input needs `debug.stagefright.c2inputsurface=-1` (`patches/c2-input-surface.patch`).

`.apkm` bundles need a Steam-style launch (`bin/steamlaunch.sh <appid> <file.apkm> [wait]`, which runs
`runner/run-steamlaunch-rootful.sh`; context `steamlaunch-<appid>`, verb `waitforexitandrun -- <path>`). It goes
through the stage's Steam entry (`compat_tool/lepton-x86_64-entry`, with `LEPTON_NO_BRIDGE=true` in place of the
Deck's Gamescope bridge), so the add-on's session hook runs exactly as on a Deck; its logs land in the runner's
`/var/lib/containers/lepton/home/lepton-logs/latest/`. A session's container IP is shown by `lepton ps`; its adbd
(TCP 5555, `ro.adb.secure=0`) accepts `adb connect` from the runner.

Android boots in ~20s with software rendering. Lepton refuses an existing profile whose runtime fingerprint
(rootfs + sysbake) differs, so switching a game to another stage needs a new app id or a reset.

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

- UNITE hangs on "Loading..." after guest login in the translator's tiered mode, which Lepton picks
  automatically after install (`baked/lepton-ndk-mode`): native `MSDKV5-Http-*` threads spin forever,
  one caught inside `HeavyOptimizeRegion → ResolveJumps → SplitBasicBlock` (`debuggerd -b <pid>`;
  `debuggerd -j` and SIGQUIT are swallowed by CrashSight). `light-translate-or-interpret` works: set
  `LEPTON_NDK_TRANSLATION_MODE` per launch, or write the mode into the game's `baked/lepton-ndk-mode`.
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
`lepton.log`, picks the NDK translation mode from `ndk-modes` by the `.apkm`'s package (unless already set),
puts a copy of `/usr/bin/gamescope` without file capabilities (`~/.cache/lepton-padmap/bin/`) first on `PATH`, and
starts `lepton-padmap session` detached. The copy is for Steam's performance overlay: `mangoapp` reads the game
window's `/proc/<pid>/fdinfo`, which for Lepton's nested gamescope with SteamOS's `cap_sys_nice` is unreadable, and
it aborts on that in a loop (each core dump freezes the game for about a second) until systemd stops restarting it. The session waits for boot, streams `logcat -b all` to `logcat-NNN` (32 MB parts, newest four kept),
installs Padmap with `cmd_real`, pushes the host's layouts (`~/.config/padmap/layouts/`, seeded from
`addon/padmap/layouts/`) into Android's `/sdcard/Padmap/`, then every 5s (re)starts Padmap's daemon as root
(Padmap's own `start.sh`, with adbd's environment; 5 failed starts max), syncs layouts both ways (editor saves
go to the host, host edits to the game) and copies new tombstones/ANRs/dropbox entries out of the profile. All
of it is logged in `session.log`. `lepton-padmap report` tars the last 5 sessions, Lepton's logcats, the
layouts and system details to `~/Desktop/lepton-report-<date>.tar.gz`. `LEPTON_PADMAP=0` skips Padmap.

Padmap reads the pad from evdev inside Android: Lepton's gamepad passthrough binds Steam Input's virtual pads
(`Microsoft X-Box 360 pad N`, 28de:11ff) present at launch, which is what a Deck provides; here
`bin/steamlaunch.sh` starts the matching virtual pad first. How Padmap maps and injects is in its
[README](addon/padmap/README.md#how-it-works).

## Steam Deck bundle

`bin/build-deck-bundle.sh [id]` builds `data/deck-dist/<id>/` (Lepton's `.tar.gz`, `.sha256`, `.install.sh`),
which goes into `bundle/` of the Deck's clone of this repo (user guide: `deck/README.md`). In the runner
(`runner/build-deck-bundle.sh`, about 70s) it copies the `gapps` stage, applies the patched entry and
`patches/c2-input-surface.patch`, sysbakes rootfully, then records that sysbake through
`lepton-customize`'s own validation (`runner/deck-record-sysbake.py` swaps only the rootless helper for the
prebuilt result) and packages with `lepton-customize package` as tool id `lepton_padmap`. On the Deck,
`deck/update.sh` pulls, and `deck/install.sh` runs Lepton's own installer for a bundle newer than the
installed one (`--replace`), then replaces the installed tool's add-on and entry with `addon/` and
`patches/lepton-x86_64-entry` (the packager only keeps Lepton's own files, so the add-on always comes from
the checkout). Lepton's runtime fingerprint covers only the rootfs, `services.jar` and the
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
