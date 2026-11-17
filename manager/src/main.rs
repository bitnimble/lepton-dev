mod app;
mod client;
mod griddb;
mod lepton;
mod pad;
mod steam;
mod vdf;

use client::SteamClient;
use std::path::{Path, PathBuf};
use std::process::Command;
use steam::{Shortcut, Steam, home};

const TITLE: &str = "Lepton Game Manager";

fn main() -> eframe::Result {
    // Steam's overlay preload lists a 32-bit library, which every 64-bit child warns about; it's loaded here already.
    // SAFETY: no other threads exist yet.
    unsafe { std::env::remove_var("LD_PRELOAD") };
    if std::env::args().nth(1).as_deref() == Some("--add-to-steam") {
        let code = match add_self_to_steam() {
            Ok(done) => {
                println!("{done}");
                0
            }
            Err(e) => {
                eprintln!("{e}");
                1
            }
        };
        std::process::exit(code);
    }
    let options = eframe::NativeOptions {
        viewport: eframe::egui::ViewportBuilder::default()
            .with_title(TITLE)
            .with_app_id("lepton-game-manager")
            .with_inner_size([1280.0, 800.0]),
        ..Default::default()
    };
    eframe::run_native(TITLE, options, Box::new(|cc| Ok(Box::new(app::App::new(cc)))))
}

/// Adds the manager to Steam's non-Steam games unless it's there already.
fn add_self_to_steam() -> Result<&'static str, String> {
    let exe = std::env::current_exe().map_err(|e| e.to_string())?;
    if Steam::locate().shortcuts().iter().any(|s| is_manager(s, &exe)) {
        return Ok("Lepton Game Manager is already in Steam");
    }
    if SteamClient::add_shortcut(TITLE, &exe, None).is_ok() {
        return Ok("Lepton Game Manager added to Steam");
    }
    // Steam's debugging port only opens once Steam restarts after the install; SteamOS's own "Add to Steam" works now
    let status = Command::new("steamos-add-to-steam")
        .arg(desktop_file())
        .status()
        .map_err(|e| format!("Steam isn't reachable and steamos-add-to-steam can't run: {e}"))?;
    if status.success() { Ok("Lepton Game Manager added to Steam") } else { Err("steamos-add-to-steam failed".into()) }
}

/// SteamOS's add-to-steam may record the desktop file rather than the binary it starts.
fn is_manager(shortcut: &Shortcut, exe: &Path) -> bool {
    shortcut.exe == exe || shortcut.exe == desktop_file()
}

fn desktop_file() -> PathBuf {
    home().join(".local/share/applications/lepton-padmap-manager.desktop")
}
