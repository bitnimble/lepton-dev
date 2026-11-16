# Lepton + Padmap on a Steam Deck

A Lepton x86_64 compatibility tool (Android 14) with Google Play services, ARM64 translation and
[Padmap](../addon/padmap/README.md), which maps the Deck's controls to on-screen touches in touch-only Android games.
The Android bundle is built by [lepton-dev](../README.md) and never committed (it contains Google components from
your own system image; personal use only); this checkout holds the installer and the add-on.

## Install

1. Desktop Mode, Konsole: `git clone <this repo> ~/lepton-dev`.
2. Copy a bundle into `~/lepton-dev/bundle/` (about 900 MB). From the build machine, with SSH enabled on the
   Deck (`passwd`, then `sudo systemctl start sshd`):
   `scp data/deck-dist/<id>/* deck@steamdeck:lepton-dev/bundle/`
3. Open `~/lepton-dev/deck/` in Dolphin and run **Install / update Lepton + Padmap** (or
   `bash ~/lepton-dev/deck/update.sh`). It downloads Google's `adb` (needs internet), installs the tool as
   `lepton_padmap` and adds desktop icons.
4. Restart Steam.

## Update

Desktop icon **Lepton: Update Lepton + Padmap** (or `bash ~/lepton-dev/deck/update.sh`), with no game running:
it runs `git pull`, then replaces the installed tool's add-on (Padmap included) and Steam entry with the
checkout's. A new bundle is needed only when the Android side changes: copy it into `bundle/` as above and run
Update; it replaces the tool in place and deletes the older bundle files. Games, sign-ins and layouts are kept
either way. Restart Steam after a bundle update.

## Add a game

1. Desktop icon **Lepton: Add Google game (lepton_padmap)**: pick the game's `.apkm`. Step 1 shows the Play
   Store: sign in to Google, tap **Done**. Step 2 opens the game, tap **Done**. Step 3 asks you to exit Steam
   and adds the shortcut. If Google says the device isn't certified, register the GSF ID the dialog shows at
   google.com/android/uncertified.
2. Gaming Mode, the game's **Controller settings > Edit Layout > Default Action Set > Always-On Command >
   System > Touchscreen Native Support**, so taps on the screen reach Android as real touches.

Pokémon UNITE gets the light ARM translator automatically (`ndk-modes` in the add-on); its default tiered
translator hangs at "Loading...".

## Controls

Padmap starts with every launch and maps the controller through the game's layout. Press **View + Menu**
(Select + Start) or tap the floating ✥ button to open the layout editor over the game:

- **+ Tap**, **+ Stick**, **+ Aim** add a control; drag it into place.
- Select a control, then press the Deck button or move the stick it should use (an aim control takes its button,
  then its stick). **−** / **+** resize it; **Save** keeps the layout; **View + Menu** or **Close** returns to the
  game.

Pokémon UNITE comes with a starting layout: left stick moves, A attacks, R1 / R2 / L2 are Move 1 / Move 2 / the
Unite Move aimed with the right stick, X uses the battle item, Y recalls. Its positions are approximate, so
check them in the editor in your first match.

Layouts are plain JSON, one file per game, in `~/.config/padmap/layouts/` (desktop icon **Lepton: Open Padmap
layouts**). They sync both ways with the running game every few seconds, so hand edits apply live and editor
saves land there. The format is in [Padmap's README](../addon/padmap/README.md#layout-files).

Steam launch options for a game: `LEPTON_PADMAP=0 %command%` turns Padmap off, `LEPTON_NDK_TRANSLATION_MODE=<mode>
%command%` overrides the translator (`tiered`, `light-translate-or-interpret`, `heavy-optimize`, `interpret-only`).

## When something breaks

Every launch writes `~/lepton-logs/<appid>-<date>-<time>/` (the newest is `~/lepton-logs/latest`):

| File | Contents |
| --- | --- |
| `session.log` | What the add-on did: boot, Padmap install and starts, layout syncs |
| `lepton.log` | Lepton's launcher output |
| `logcat.txt` | All of Android's logs (`logcat -b all`; Padmap's lines are tagged `Padmap`) |
| `tombstones/`, `anr/`, `system/dropbox/` | Native crashes, ANRs and crash reports from that launch |

To report a problem, use the desktop icon **Lepton: Save crash report** (or `~/.local/bin/lepton-padmap report`):
it writes `~/Desktop/lepton-report-<date>.tar.gz` with the last five launches, Lepton's own logcats, your layouts
and system details. Send that file. **Lepton: Open logs** opens the folder.

Padmap is restarted automatically if it stops (up to five failed starts per launch, logged in `session.log`).
