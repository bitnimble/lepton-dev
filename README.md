# lepton-dev

Headless dev loop for [Lepton x86_64](https://github.com/pjohno/lepton-x86_64) (community x86_64 port of
Valve's Lepton, Android 14 in podman) on the docker host, without a GPU or Steam.

## Layout

| Path | Contents |
| --- | --- |
| `runner/` | Files that run **inside** `lepton-runner`: image (`Containerfile`), env, launch/sysbake/stage scripts |
| `bin/` | Host-side helpers (run from this dev container via the docker socket) |
| `host/` | Scripts that ran as **root on the docker host** (via privileged `nsenter`); see Host changes |
| `patches/` | Patches to the release's `compat_tool/liblepton/` (`*.patch`), with the patched `liblepton.sh` and `properties.sh` that `bin/push.sh` installs |
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
bin/mantis-buddy.sh [ctx]; bin/install-mantis.sh [ctx]              # Mantis buddy (re)start; Mantis install
```

### Browser remote control

`http://<docker host>:3459/` serves [ws-scrcpy](https://github.com/NetrisTV/ws-scrcpy) from the runner
(`ws-scrcpy.service`, `runner/ws-scrcpy.sh`; built once into the volume by `runner/ws-scrcpy-setup.sh`).
It keeps adb connected to every running session; pick the device, then **Broadway.js** (WebCodecs needs
HTTPS). Video, touch, keyboard and the nav buttons all go through the one HTTP port ("proxy over adb").
Phone browsers get real multi-touch: each browser touch point becomes its own Android pointer (two
simultaneous CDP touches showed as `P: 2/2` with `settings put system pointer_location 1`).
`runner/ws-scrcpy-lepton.patch` adds an **Open Mantis** toolbar button (gamepad icon; server route
`POST /lepton/launch?udid=…&app=mantis` runs `am start -n app.mantispro.gamepad/.MainActivity`; Back returns
to the game), keeps fit-to-screen encode bounds landscape, so a portrait phone still gets a landscape-sized
stream, and makes the keyboard toggle work on phones: it focuses an off-screen field (opening the on-screen
keyboard) whose edits are diffed and forwarded as text injection + `DEL`/`ENTER` keys; physical keys still go
through scrcpy key events. Text injection is limited to characters Android's key map can type (ASCII). Encoder Surface input needs `debug.stagefright.c2inputsurface=-1` (`patches/c2-input-surface.patch`).

Steam launches stream `logcat -b all` to `run/<ctx>.logcat.stream` (Lepton's own shutdown capture misses
early exits).

`.apkm` bundles need a Steam-style launch (`bin/steamlaunch.sh <appid> <file.apkm> [wait]`, which runs
`runner/run-steamlaunch-rootful.sh`; context `steamlaunch-<appid>`, verb `waitforexitandrun -- <path>`). A session's container IP is shown by
`lepton ps`; its adbd (TCP 5555, `ro.adb.secure=0`) accepts `adb connect` from the runner.

Android boots in ~20s with software rendering. Lepton refuses an existing profile whose runtime fingerprint
(rootfs + sysbake) differs, so switching a game to another stage needs a new app id or a reset.

## Status

| Item | State |
| --- | --- |
| Fossify Calculator (x86_64) | Runs; injected taps work (`docs/screens/calculator-input.png`) |
| AAAAXY 1.8.34 arm64-only | Renders in-game via `libndk_translation` (`docs/screens/aaaaxy-arm64.png`) |
| Pokémon UNITE 1.25.1.1 (`jp.pokemon.pokemonunite`) | Guest account, onboarding, lobby with 3D models (`docs/screens/unite-lobby.png`) on `gapps` (appid 900002, light translator mode); bot match returns to the challenge screen after VS |
| Mantis Gamepad Pro 3.4.9.1 (`app.mantispro.gamepad`) | Signed in, buddy connected, virtual pad detected; a mapped pad button taps UNITE's Start (`docs/screens/mantis-mapped-start.png`) |
| UNITE frame rate (software rendering, SurfaceFlinger `--timestats`) | ~25.5 fps on the challenge screen, ~23 fps on the 3D VS screen |

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
  configuration change (`am_kill … resetConfig`). Open other apps over the game (Mantis button, Back to return)
  rather than going Home.
- Steam launches occasionally exit within 30s of boot (cause not yet captured; see the logcat stream).
- Lepton's `cmd` wrapper (`/system/bin/cmd`, so also `pm` and `adb install`) treats every install as the game
  and moves the game's installed dir into `/data/steam_app`. That leaves overlay whiteouts over the game's
  `baked/app_overlay/*.apk` and `lib/`; the running game survives on open files, but the next launch fails
  validation ("installed codePath or app_overlay/base.apk missing"). Install other apps with `cmd_real`
  (`bin/install-mantis.sh`, `bin/mantis-buddy.sh`). Repair: replace the whiteouts with the files from
  `lepton-apkm/<hash>/` and re-extract `lib/arm64` from the arm64 split.
- A portrait-only app (Mantis) rotates the whole display; Unity then loses its surface. `start-buddy.sh`
  locks the user rotation (persists in the profile's `/data`).
- Child processes of a translated app fail to link: Mantis's periodic `su`/`sh` spawns log `CANNOT LINK
  EXECUTABLE "sh": cannot locate symbol "__android_log_write" referenced by "/system/lib64/liblepton_ndk_auxv.so"`.
- SurfaceFlinger `--latency` has no data (no present fences); `--timestats` gives per-layer FPS.
- Toybox `grep -E` with alternations segfaults inside Android; grep logcat on the runner side (`bin/diag.sh`).

## Mantis buddy

Mantis needs a privileged helper daemon (MantisBuddy, `app.mantispro.injector.injection.InjectServiceKt` in
the bundle's `mantis.dex`, control port 9999). Its native lib `libmantis.so` is **ARM64-only**. Upstream runs
it under `app_process` as shell/root, which on x86 is native x86_64 and never gets the native bridge
(`dlopen` fails `EM_AARCH64 instead of EM_X86_64`); a plain arm64 app gets the bridge but has a real app
uid, so privileged calls fail (`INJECT_EVENTS`).

Activation: Mantis is signed in and its bundle installed via the APK's documented PC-activation path
(`adb shell su 0 sh /sdcard/Android/data/app.mantispro.gamepad/files/buddyNew.sh`; the one-time enrollment
credential it consumes is backed up at `/root/mantis-enrollment.bak` in the runner). Its own launcher then
fails (the `app_process` problem above).

`bin/mantis-buddy.sh [ctx]` starts the daemon instead: it installs `data/mantis-buddy/host.apk`
(`mantis-buddy/host/build.sh`) and runs `mantis-buddy/start-buddy.sh` in the guest, which does
`am instrument --abi arm64-v8a --no-hidden-api-checks lepton.mantisbuddy/.BuddyHost` as root. That forks
`com.android.DeviceAsWebcam` (uid 1000, so `primaryCpuAbi` is non-null and the ABI override applies) with the
aarch64 translator. Debuggable builds let a root caller skip the instrumentation signature check, and an
instrumented process gets its source uid's (root's) permissions. `BuddyHost` loads `mantis.dex` with a
boot-parent `DexClassLoader` (the target apk bundles a clashing kotlin), a library path containing
`/lib/arm` (ndk_translation's test for bridging a namespace), and sets `java.class.path` through
`System.unchangeableProps`, which the daemon reads to find its bundle. It also re-parents the system class
loader onto that loader: JNI `FindClass` on the daemon's native threads resolves through the system loader,
which under `app_process` holds `mantis.dex`. The Mantis app then shows "Mantis Buddy Connected".
`runner/run-steamlaunch-rootful.sh` starts the buddy after boot whenever the host apk is installed.

The daemon reads gamepads straight from `/dev/input/event*`. Lepton's gamepad passthrough binds Steam Input's
virtual pads (`Microsoft X-Box 360 pad N`, 28de:11ff) present at launch, which is what a Deck provides;
here `bin/steamlaunch.sh` starts the matching virtual pad first. Mantis grabs the pad (`EVIOCGRAB`) and
injects touches. Its default engine ("Empusa") needs `/dev/uinput`, which Android doesn't get (the daemon runs
as uid 1000, and a `chmod` there would change the host node through the bind mount); enable Mantis
Settings → **Legacy Touch Engine** ("Orchid": InputManager injection, allowed by the instrumentation's root
permissions). The app re-sends that choice whenever the buddy connects.

Mantis also derives orientation from the display rotation the phone way (rotation 0 = portrait) and logs
`OrientationCheck ... mismatch=true` with a 767x1279 overlay on Lepton's landscape-natural display, so
`start-buddy.sh` presents the display as portrait-natural turned 90 degrees (`wm size <h>x<w>`,
`wm user-rotation lock 1`). Lepton's host input arrives as injected display-coordinate events (device -1),
so it isn't rotated twice.

Mapping flow: Mantis home → Add Game → launch the game from its tile (spends a free credit) → floating icon →
Key → press a pad button → drag the widget onto the target → close the editor. A mapped pad button pressing
UNITE's Start reached the VS screen (`docs/screens/mantis-mapped-start.png`). A buddy restart re-arms the
mapping on the next launch from Mantis.

Mantis also ships its own ADB client (`libmantis_adb_crypto.so`) for Wi-Fi-debugging activation; the
PC-activation path above avoids needing it.

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
