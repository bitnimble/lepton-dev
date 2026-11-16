# Lepton + Mantis on a Steam Deck

A Lepton x86_64 compatibility tool (Android 14) with Google Play services, ARM64 translation and the Mantis
Gamepad Pro add-on: Mantis maps the Deck's controls to on-screen touches in Android games. Built from
[lepton-dev](../README.md); for personal use (it contains Google components from your own system image).

## Install

1. Copy this folder to the Deck as `~/Downloads/lepton-mantis/` (about 900 MB). From the build machine, with SSH
   enabled on the Deck (`passwd`, then `sudo systemctl start sshd`):
   `scp -r data/deck-dist/<id> deck@steamdeck:Downloads/lepton-mantis`
2. Desktop Mode: open the folder in Dolphin and run **Install Lepton + Mantis** (or, in Konsole,
   `bash ~/Downloads/lepton-mantis/install.sh`). It downloads Google's `adb` (needs internet), installs the tool
   as `lepton_mantis` and adds desktop icons. Running it again with a newer build replaces the tool in place;
   games, sign-ins and Mantis setup live in Steam's game data and are kept.
3. Restart Steam.

## Add a game

1. Desktop icon **Lepton: Add Google game (lepton_mantis)**: pick the game's `.apkm`. Step 1 shows the Play
   Store: sign in to Google, tap **Done**. Step 2 opens the game (Mantis opens over it once it's up; the one-time
   Mantis setup below can be done here), tap **Done**. Step 3 asks you to exit Steam and adds the shortcut. If
   Google says the device isn't certified, register the GSF ID the dialog shows at
   google.com/android/uncertified.
2. Gaming Mode, the game's **Controller settings > Edit Layout > Default Action Set > Always-On Command >
   System > Touchscreen Native Support** (so you can tap Mantis and Android).

Pokémon UNITE gets the light ARM translator automatically (`ndk-modes` in the add-on); its default tiered
translator hangs at "Loading...".

## Mantis, first launch of a game

Launch the game from Steam. When Android is up, the add-on installs Mantis, keeps the display in the orientation
Mantis expects, and opens Mantis over the game. Once per game:

1. Sign in to Mantis (Google).
2. Activate the buddy with Mantis's **PC (ADB) activation**. The add-on runs the activation command it stages
   within a few seconds; Mantis then shows **MantisBuddy is Connected**.
3. Mantis **Settings > Legacy Touch Engine**: on. The default engine needs `/dev/uinput` inside Android, which
   this setup deliberately doesn't give it.
4. **Add Game**, pick the game, tap its tile, **Launch Game**, then map buttons with the floating Mantis icon.

## Every launch

Mantis opens over the game: tap the game's tile, then **Launch Game** (on the free tier this spends a credit, as
on a phone). Mantis's only way to arm a mapping is that button, so the add-on opens Mantis instead of pressing
it for you.

Steam launch options for a game: `LEPTON_MANTIS=0 %command%` skips Mantis entirely, `LEPTON_MANTIS_OPEN=0
%command%` keeps it from opening at startup, `LEPTON_NDK_TRANSLATION_MODE=<mode> %command%` overrides the
translator (`tiered`, `light-translate-or-interpret`, `heavy-optimize`, `interpret-only`).

## When something breaks

Every launch writes `~/lepton-logs/<appid>-<date>-<time>/` (the newest is `~/lepton-logs/latest`):

| File | Contents |
| --- | --- |
| `session.log` | What the add-on did: boot, Mantis install, buddy activation/starts/restarts |
| `lepton.log` | Lepton's launcher output |
| `logcat.txt` | All of Android's logs (`logcat -b all`) |
| `tombstones/`, `anr/`, `system/dropbox/` | Native crashes, ANRs and crash reports from that launch |

To report a problem, use the desktop icon **Lepton: Save crash report** (or `~/.local/bin/lepton-mantis report`):
it writes `~/Desktop/lepton-report-<date>.tar.gz` with the last five launches, Lepton's own logcats and system
details. Send that file. **Lepton: Open logs** opens the folder.

The buddy is restarted automatically if it dies (up to five failed starts per launch, logged in `session.log`).
