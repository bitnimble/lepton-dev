mod app;
mod client;
mod griddb;
mod lepton;
mod pad;
mod steam;
mod vdf;

fn main() -> eframe::Result {
    let options = eframe::NativeOptions {
        viewport: eframe::egui::ViewportBuilder::default()
            .with_title("Lepton Game Manager")
            .with_app_id("lepton-game-manager")
            .with_inner_size([1280.0, 800.0]),
        ..Default::default()
    };
    eframe::run_native("Lepton Game Manager", options, Box::new(|cc| Ok(Box::new(app::App::new(cc)))))
}
