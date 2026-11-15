# lepton-dev

Headless dev loop for [Lepton x86_64](https://github.com/pjohno/lepton-x86_64) (community x86_64 port of
Valve's Lepton, Android 14 in podman) on the docker host, without a GPU or Steam.

## Layout

| Path | Contents |
| --- | --- |
| `runner/` | Files that run **inside** `lepton-runner`: image (`Containerfile`), env, launch/sysbake/stage scripts |
| `bin/` | Host-side helpers (run from this dev container via the docker socket) |
| `host/` | Scripts that ran as **root on the docker host** (via privileged `nsenter`); see Host changes |
| `patches/` | Rootful patch to the release's `compat_tool/liblepton/liblepton.sh` (`liblepton.sh` is the patched file) |
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
- `LEPTON_ADB=/usr/bin/adb` (Fedora `android-tools`), `LEPTON_FORCE_SOFTWARE=true` (image ships AMD drivers only).

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
```

`.apkm` bundles need a Steam-style launch (`runner/run-steamlaunch-rootful.sh <appid> <file.apkm> [wait]`,
context `steamlaunch-<appid>`, verb `waitforexitandrun -- <path>`). A session's container IP is shown by
`lepton ps`; its adbd (TCP 5555, `ro.adb.secure=0`) accepts `adb connect` from the runner.

Android boots in ~20s with software rendering. Lepton refuses an existing profile whose runtime fingerprint
(rootfs + sysbake) differs, so switching a game to another stage needs a new app id or a reset.

## Status

| Item | State |
| --- | --- |
| Fossify Calculator (x86_64) | Runs; injected taps work (`docs/screens/calculator-input.png`) |
| AAAAXY 1.8.34 arm64-only | Renders in-game via `libndk_translation` (`docs/screens/aaaaxy-arm64.png`) |
| Pokémon UNITE 1.25.1.1 (`jp.pokemon.pokemonunite`) | Installs, downloads update, interactive; guest onboarding in progress on `gapps` (appid 900002) |
| Mantis Gamepad Pro 3.4.9.1 (`app.mantispro.gamepad`) | Installs/runs (Flutter, arm64); requires Google sign-in, so needs the `gapps` stage |

## Known issues

- `/data/media/0` symlinks to a host compatdata path not visible in the container: OBB links and
  `/storage/emulated/0` fail (`vold: Failed to find mounted volume`).
- Lepton's install hook treats every `pm install` as the game: installing a second app re-runs the game's
  `/data/steam_app` move (harmless "Cross-device link" errors).
- A portrait-only app (Mantis) rotates the whole display; Unity then loses its surface. Lock landscape:
  `wm fixed-to-user-rotation enabled; wm user-rotation lock 0` (persists in the profile's `/data`).
- Toybox `grep -E` with alternations segfaults inside Android; grep logcat on the runner side (`bin/diag.sh`).

## Mantis buddy

Mantis ships its own ADB client (`libmantis_adb_crypto.so`) and an activation module
(`app.mantispro.gamepad.activation`: bundle installer, launch coordinator, handshake). It pushes a buddy
bundle under `/data/local/tmp` and starts it from a `#!/system/bin/sh` bootstrap over adb. Lepton's adbd on
TCP 5555 with `ro.adb.secure=0` should let its client connect without pairing.

## Host changes (docker host, root)

Every root command was reviewed first by a no-context subagent for impact on the host and other containers.

- `binder_linux` loaded (kernel marks it `[permanent]`), `/etc/modules-load.d/binder.conf`.
- Sysbox 0.7.1 installed manually (`host/host-stage-sysbox.sh`, `host/host-install-sysbox.sh`), skipping the
  `.deb` postinst (it would add `bip: 172.20.0.1/16`, clashing with the `172.17.0.0/12` pool): binaries in
  `/usr/bin`, units in `/etc/systemd/system`, `sysbox` user + subids `231072:1048576`,
  `/etc/sysctl.d/99-sysbox.conf`, `daemon.json` runtime `sysbox-runc` (backup `daemon.json.bak-pre-sysbox`,
  applied by SIGHUP; `live-restore` is on).
- `/usr/bin/sysbox-fs` replaced by a static build of nestybox/sysbox-fs master `201ec13`
  (`host/Dockerfile.sysbox-fs`, `host/host-swap-sysbox-fs.sh`); original at `/usr/bin/sysbox-fs.0.7.1`.
