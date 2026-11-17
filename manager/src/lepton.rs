use crate::steam::{Shortcut, Tool, home};
use std::fs;
use std::io::{self, Read, Write};
use std::path::{Path, PathBuf};
use std::process::Command;

const SLOT_MARKER: &[u8] = b"lepton-play-slot";
const LAUNCH_RECORD: &str = "lepton-launch-package";
const OPEN_PLAY_STORE: &str = "lepton-open-play-store";
const SETUP_GOOGLE: &str = "lepton-setup-google";

pub fn is_game(shortcut: &Shortcut) -> bool {
    shortcut
        .exe
        .extension()
        .and_then(|e| e.to_str())
        .is_some_and(|e| e.eq_ignore_ascii_case("apk") || e.eq_ignore_ascii_case("apkm"))
}

pub fn is_slot(exe: &Path) -> bool {
    let mut head = [0u8; SLOT_MARKER.len()];
    fs::File::open(exe).and_then(|mut f| f.read_exact(&mut head)).is_ok() && head == SLOT_MARKER
}

/// A new Play slot file named after the game; never reuses an existing one.
pub fn new_slot(name: &str) -> io::Result<PathBuf> {
    let dir = home().join(".local/share/lepton-padmap/play");
    fs::create_dir_all(&dir)?;
    let base: String = name.chars().map(|c| if c.is_ascii_alphanumeric() || " ._-".contains(c) { c } else { '_' }).collect();
    let base = base.trim();
    let base = if base.is_empty() { "Play game" } else { base };
    for n in 1.. {
        let file = dir.join(if n == 1 { format!("{base}.apkm") } else { format!("{base} {n}.apkm") });
        match fs::OpenOptions::new().write(true).create_new(true).open(&file) {
            Ok(mut handle) => {
                handle.write_all(b"lepton-play-slot\n")?;
                return Ok(file);
            }
            Err(e) if e.kind() == io::ErrorKind::AlreadyExists => continue,
            Err(e) => return Err(e),
        }
    }
    unreachable!()
}

pub fn launch_package(compat: &Path) -> Option<String> {
    let package = fs::read_to_string(compat.join(LAUNCH_RECORD)).ok()?;
    let package = package.trim();
    (!package.is_empty()).then(|| package.to_string())
}

pub fn set_launch_package(compat: &Path, package: &str) -> io::Result<()> {
    if !is_package_name(package) {
        return Err(io::Error::new(io::ErrorKind::InvalidInput, "not an Android package name"));
    }
    fs::create_dir_all(compat)?;
    fs::write(compat.join(LAUNCH_RECORD), format!("{package}\n"))
}

pub fn play_store_requested(compat: &Path) -> bool {
    compat.join(OPEN_PLAY_STORE).is_file()
}

/// The next launch opens the Play Store (for a Play slot, the newest app installed there becomes its game).
pub fn request_play_store(compat: &Path, on: bool) -> io::Result<()> {
    let flag = compat.join(OPEN_PLAY_STORE);
    if !on {
        return fs::remove_file(flag).or_else(|e| if e.kind() == io::ErrorKind::NotFound { Ok(()) } else { Err(e) });
    }
    fs::create_dir_all(compat)?;
    fs::write(flag, b"")
}

/// The next launch only lets Play update itself and Google Play services, then closes by itself.
pub fn request_google_setup(compat: &Path) -> io::Result<()> {
    fs::create_dir_all(compat)?;
    fs::write(compat.join(SETUP_GOOGLE), b"")
}

/// Apps installed in the profile (from its /data/app), Padmap excluded.
pub fn installed_packages(compat: &Path) -> Vec<String> {
    let apps = compat.join("baked/data_overlay/app");
    let Ok(output) = Command::new("podman")
        .args(["unshare", "find"])
        .arg(&apps)
        .args(["-mindepth", "2", "-maxdepth", "2", "-type", "d", "-printf", "%f\\n"])
        .output()
    else {
        return Vec::new();
    };
    let mut packages: Vec<String> = String::from_utf8_lossy(&output.stdout)
        .lines()
        // <package>-<url-safe base64>: package names have no '-', the suffix may
        .filter_map(|dir| dir.split_once('-').map(|(package, _)| package.to_string()))
        .filter(|p| is_package_name(p) && p != "app.padmap")
        .collect();
    packages.sort();
    packages.dedup();
    packages
}

/// Google's device ID, for registering an uncertified device at google.com/android/uncertified.
pub fn gsf_id(tool: &Tool, compat: &Path) -> Option<String> {
    let reader = tool.root.join("tests/runtime/read-gsf-id.py");
    let db = compat.join("baked/data_overlay/data/com.google.android.gsf/databases/gservices.db");
    let output = Command::new("podman").args(["unshare", "python3"]).arg(reader).arg(db).output().ok()?;
    let id = String::from_utf8_lossy(&output.stdout).trim().to_string();
    (output.status.success() && !id.is_empty() && id.chars().all(|c| c.is_ascii_digit())).then_some(id)
}

/// Removes the game's Android profile (sign-in, installed apps, saves). Android owns files there, so it goes
/// through podman's user namespace.
pub fn delete_profile(compat: &Path) -> io::Result<()> {
    if !compat.is_dir() {
        return Ok(());
    }
    let status = Command::new("podman").args(["unshare", "rm", "-rf", "--one-file-system", "--"]).arg(compat).status()?;
    if status.success() { Ok(()) } else { Err(io::Error::other("podman unshare rm failed")) }
}

fn is_package_name(s: &str) -> bool {
    !s.is_empty() && s.chars().all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '.')
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn launch_record_and_play_store_flag() {
        let dir = std::env::temp_dir().join(format!("lepton-manager-record-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        assert_eq!(launch_package(&dir), None);
        set_launch_package(&dir, "jp.pokemon.pokemonunite").unwrap();
        assert_eq!(launch_package(&dir).as_deref(), Some("jp.pokemon.pokemonunite"));
        assert!(set_launch_package(&dir, "x; rm -rf /").is_err());
        assert!(!play_store_requested(&dir));
        request_play_store(&dir, true).unwrap();
        assert!(play_store_requested(&dir));
        request_play_store(&dir, false).unwrap();
        request_play_store(&dir, false).unwrap();
        assert!(!play_store_requested(&dir));
        request_google_setup(&dir).unwrap();
        assert!(dir.join("lepton-setup-google").is_file(), "the flag entry-hook.sh looks for");
        fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn slot_files() {
        let file = std::env::temp_dir().join(format!("lepton-manager-slot-{}.apkm", std::process::id()));
        fs::write(&file, b"lepton-play-slot\n").unwrap();
        assert!(is_slot(&file));
        fs::write(&file, b"PK\x03\x04").unwrap();
        assert!(!is_slot(&file));
        fs::remove_file(file).unwrap();
        let game = |exe: &str| is_game(&Shortcut { appid: 1, name: String::new(), exe: PathBuf::from(exe) });
        assert!(game("/a/b.APKM") && game("/a/b.apk") && !game("/usr/bin/firefox"));
    }
}
