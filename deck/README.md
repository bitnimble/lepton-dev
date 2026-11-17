# Lepton + Padmap on a Steam Deck

A Lepton x86_64 compatibility tool (Android 14) with Google Play services, ARM64 translation and
[Padmap](../addon/padmap/README.md), which maps the Deck's controls to on-screen touches in touch-only Android games.
This checkout holds the installer and the add-on. The Android part is built on the Deck itself from Lepton's
release (GitHub) and Google's Android 14 Play system image (dl.google.com), downloaded from those official
sources; nothing with Google components is redistributed.

## Install

1. Desktop Mode, Konsole: `git clone https://github.com/bitnimble/lepton-dev ~/lepton-dev`.
2. Open `~/lepton-dev/deck/` in Dolphin and run **Install / update Lepton + Padmap** (or
   `bash ~/lepton-dev/deck/update.sh`). The first run downloads about 2 GB and builds the Android bundle (15
   minutes or more, about 8 GB free space needed while building), then Lepton's installer downloads Google's `adb`,
   installs the tool as `lepton_padmap`, adds the **Lepton Game Manager** desktop icon and adds the manager to your
   Steam library (under Non-Steam) for Gaming Mode.
3. Restart Steam (it then opens the local port the Game Manager talks to it through).

## Lepton Game Manager

Everything else happens in the Game Manager, from Desktop or Gaming Mode, with the controller (A selects, B goes
back; Steam + X opens the keyboard). Changes apply to the running Steam: it never has to be closed.

- **Add a game**: from **Google Play** (name it; its first launch opens the Play Store: sign in, install the game,
  quit, and the app you installed becomes the shortcut's game) or from an `.apk` / `.apkm` file in Downloads,
  Desktop or your home folder. Each game gets its own Android, with its own Google sign-in and saves.
- A game's page: **Play**, **Game** (for Play games: which installed app it launches, or pick another in the Play
  Store on next launch), **Name**, **Runtime** (which installed Lepton runs it), **Artwork** (capsule, header,
  hero, logo and icon, from an image file or from SteamGridDB with your API key in **Settings**), **Open the Play
  Store on next launch** (sign in to Google again), the **Google device ID** (if Google says the device isn't
  certified, register it at google.com/android/uncertified) and **Remove** (optionally with the game's data).
- **Runtimes** lists the installed Lepton tools; **Update Lepton + Padmap** pulls this checkout and reinstalls,
  **Save crash report** writes one to the Desktop.
- **Settings**: **UI zoom** (A steps through 75% to 200%) and the SteamGridDB API key.

The first time, the manager may ask to connect to Steam: **Allow**, then restart Steam once. It uses Steam's
local debugging port (127.0.0.1:8080, the same one Decky Loader uses), which lets local programs control Steam.

In Gaming Mode, also set each game's **Controller settings > Edit Layout > Default Action Set > Always-On Command
> System > Touchscreen Native Support**, so taps on the screen reach Android as real touches.

Launch options still work too (**Properties > General**): `LEPTON_PLAY_ONLY=true %command%` opens the Play Store
(the newest installed app becomes a Play game's game; remove the option afterwards), and
`LEPTON_LAUNCH_PACKAGE=<package name> %command%` makes a Play game launch that package from now on.

The update keeps games, sign-ins and layouts, and rebuilds the Android bundle when the update moves to a new
Android build (restart Steam afterwards). A bundle copied into `~/lepton-dev/bundle/` (e.g. a test build from
lepton-dev's `bin/build-deck-bundle.sh`) is installed instead of building. Without the manager:
`bash ~/lepton-dev/deck/update.sh`.

Lepton picks the ARM translator mode per game: the fast tiered mode when the game's code allows it (Pokémon
UNITE does), falling back to the light mode for the next launch if a game exits early in tiered. The add-on
supplies a fixed copy of Google's translator, without which tiered mode hangs UNITE at "Loading..."; game files
are untouched. If a game misbehaves in tiered, launch option `LEPTON_NDK_TRANSLATION_MODE=light-translate-or-interpret
%command%` forces the light mode.

## Controls

Padmap starts with every launch and maps the controller through the game's layout. Press **View + Menu**
(Select + Start) to open the layout editor over the game:

- **+ Tap**, **+ Stick**, **+ Aim** add a control, already selected (yellow). Drag it onto the game's button.
- Bind it from the Deck. A tap: press its button. A stick: move the stick. An aim: press its button, then move
  the stick that aims it (the label shows `LB+?` until you do). The style menu next to **Done** shows the buttons
  as Steam (the Deck's own labels), Xbox, Nintendo or PlayStation ones.
- Tap a control to select it again and rebind, move or resize it. **Smaller** / **Larger** resize, **Delete**
  removes it (these appear while a control is selected).
- A selected aim has a checkbox, **Aim with LS when RS is idle** (off by default): the other stick aims the skill
  while its own stick is untouched, e.g. cast in the direction you're walking.
- **View + Menu** or **Done** saves any changes and returns to the game.

For example, an aim skill on L1 aimed with the right stick: **+ Aim**, drag it onto the skill, press **L1**, push
the **right stick**, **Done**.

While Padmap maps a game, the game's vibrations rumble the Deck (Steam's controller settings for the game must
allow rumble). `session.log`'s Padmap lines say `rumble: ... has N motor(s)`; 0 means Steam's virtual controller
didn't offer rumble to Android.

Pokémon UNITE comes with a starting layout: left stick moves, A attacks, R1 / R2 / L2 are Move 1 / Move 2 / the
Unite Move aimed with the right stick, X uses the battle item, Y recalls. Its positions are approximate, so
check them in the editor in your first match.

Layouts are plain JSON, one file per game, in `~/.config/padmap/layouts/`. They sync both ways with the running game every few seconds, so hand edits apply live and editor
saves land there. The format is in [Padmap's README](../addon/padmap/README.md#layout-files).

Steam launch options for a game: `LEPTON_PADMAP=0 %command%` turns Padmap off, `LEPTON_NDK_TRANSLATION_MODE=<mode>
%command%` overrides the translator (`tiered`, `light-translate-or-interpret`, `heavy-optimize`, `interpret-only`).

## When something breaks

Every launch writes `~/lepton-logs/<appid>-<date>-<time>/` (the newest is `~/lepton-logs/latest`):

| File | Contents |
| --- | --- |
| `session.log` | What the add-on did: boot, Padmap install and starts, layout syncs |
| `lepton.log` | Lepton's launcher output |
| `logcat-000`, `logcat-001`, … | All of Android's logs (`logcat -b all`; Padmap's lines are tagged `Padmap`), in 32 MB parts; the newest four are kept |
| `tombstones/`, `anr/`, `system/dropbox/` | Native crashes, ANRs and crash reports from that launch |

To report a problem, use **Save crash report** in the Game Manager (or `~/.local/bin/lepton-padmap report`): it
writes `~/Desktop/lepton-report-<date>.tar.gz` with the last five launches, Lepton's own logcats, your layouts,
system details and this boot's kernel journal and user-session journal (Steam, Gamescope and crash lines only:
GPU resets, overlay crashes), so save it before rebooting. Send that file.

Steam's performance overlay works because the add-on runs Lepton's Gamescope from a capability-free copy in
`~/.cache/lepton-padmap/bin/`; if the overlay freezes the game every few seconds or vanishes, include a report.

Padmap is restarted automatically if it stops (up to five failed starts per launch, logged in `session.log`).
