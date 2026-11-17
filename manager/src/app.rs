use crate::client::{Artwork, SteamClient};
use crate::griddb::{GridDb, Image};
use crate::lepton;
use crate::pad::Pad;
use crate::steam::{Steam, Tool, home};
use eframe::egui::{
    self, Align, Align2, Color32, ColorImage, Context, FontId, Key, RichText, ScrollArea, Sense, TextureHandle, TextureOptions,
    vec2,
};
use std::collections::{HashMap, HashSet};
use std::io::{BufRead, BufReader};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::mpsc::{Receiver, Sender, channel};
use std::time::Duration;

const ACCENT: Color32 = Color32::from_rgb(26, 159, 255);
const DIM: Color32 = Color32::from_rgb(154, 168, 184);
const DANGER: Color32 = Color32::from_rgb(229, 72, 77);
const THUMB: f32 = 180.0;

#[derive(Clone, Debug)]
struct Game {
    appid: u32,
    name: String,
    exe: PathBuf,
    tool: Option<String>,
    slot: bool,
    package: Option<String>,
    play_store_next: bool,
}

#[derive(Clone, Debug, PartialEq)]
enum Source {
    Play,
    File(PathBuf),
}

#[derive(Clone, Debug)]
enum Screen {
    Home,
    Game(u32),
    ChangeGame(u32),
    Rename(u32, String),
    Runtime(u32),
    Artwork(u32),
    ArtworkSource(u32, Option<Artwork>),
    LocalImages(u32, Option<Artwork>),
    GridGames(u32, Option<Artwork>),
    GridImages(u32, Option<Artwork>),
    Remove(u32),
    AddSource,
    AddFile,
    AddName(Source, String),
    AddRuntime(Source, String),
    Added(u32, bool),
    Connect,
    Settings(String),
    Task(String),
}

enum Msg {
    Connected(bool),
    Done(Result<String, String>),
    Packages(u32, Vec<String>),
    Gsf(u32, Option<String>),
    Added(Result<(u32, String, PathBuf, String), String>),
    GridGames(Result<Vec<(u64, String)>, String>),
    GridImages(Result<Vec<Image>, String>),
    Thumb(String, Option<ColorImage>),
    TaskLine(String),
    TaskEnd(bool),
}

/// Session-local view of changes Steam may not have written to its files yet.
#[derive(Default)]
struct Overrides {
    added: Vec<Game>,
    names: HashMap<u32, String>,
    tools: HashMap<u32, String>,
    removed: HashSet<u32>,
    self_added: bool,
}

pub struct App {
    steam: Steam,
    repo: PathBuf,
    games: Vec<Game>,
    tools: Vec<Tool>,
    in_steam: bool,
    overrides: Overrides,
    stack: Vec<Screen>,
    focus_first: bool,
    first_widget: bool,
    tx: Sender<Msg>,
    rx: Receiver<Msg>,
    ctx: Context,
    busy: Option<String>,
    status: Option<(String, bool)>,
    connected: Option<bool>,
    griddb_key: String,
    pad: Pad,
    packages: HashMap<u32, Vec<String>>,
    gsf: HashMap<u32, Option<String>>,
    grid_games: Vec<(u64, String)>,
    grid_images: Vec<Image>,
    textures: HashMap<String, TextureHandle>,
    thumbs_requested: HashSet<String>,
    task_log: Vec<String>,
    task_running: bool,
}

impl App {
    pub fn new(cc: &eframe::CreationContext<'_>) -> App {
        App::with_steam(cc, Steam::locate())
    }

    fn with_steam(cc: &eframe::CreationContext<'_>, steam: Steam) -> App {
        style(&cc.egui_ctx);
        let (tx, rx) = channel();
        let repo = std::env::current_exe()
            .ok()
            .and_then(|exe| Some(exe.parent()?.parent()?.to_path_buf()))
            .unwrap_or_else(|| home().join("lepton-dev"));
        let mut app = App {
            steam,
            repo,
            games: Vec::new(),
            tools: Vec::new(),
            in_steam: true,
            overrides: Overrides::default(),
            stack: vec![Screen::Home],
            focus_first: true,
            first_widget: true,
            tx,
            rx,
            ctx: cc.egui_ctx.clone(),
            busy: None,
            status: None,
            connected: None,
            griddb_key: settings_read(),
            pad: Pad::new(),
            packages: HashMap::new(),
            gsf: HashMap::new(),
            grid_games: Vec::new(),
            grid_images: Vec::new(),
            textures: HashMap::new(),
            thumbs_requested: HashSet::new(),
            task_log: Vec::new(),
            task_running: false,
        };
        app.refresh();
        app.check_connection();
        app
    }

    fn refresh(&mut self) {
        let mapping = self.steam.tool_mapping();
        let mut games: Vec<Game> = self
            .steam
            .shortcuts()
            .into_iter()
            .filter(lepton::is_game)
            .filter(|s| !self.overrides.removed.contains(&s.appid))
            .map(|s| {
                let compat = self.steam.compatdata(s.appid);
                Game {
                    appid: s.appid,
                    slot: lepton::is_slot(&s.exe),
                    package: lepton::launch_package(&compat),
                    play_store_next: lepton::play_store_requested(&compat),
                    tool: mapping.get(&s.appid).cloned(),
                    name: s.name,
                    exe: s.exe,
                }
            })
            .collect();
        for added in &self.overrides.added {
            if !games.iter().any(|g| g.appid == added.appid) && !self.overrides.removed.contains(&added.appid) {
                games.push(added.clone());
            }
        }
        for game in &mut games {
            if let Some(name) = self.overrides.names.get(&game.appid) {
                game.name = name.clone();
            }
            if let Some(tool) = self.overrides.tools.get(&game.appid) {
                game.tool = Some(tool.clone());
            }
        }
        games.sort_by_key(|g| g.name.to_lowercase());
        self.games = games;
        let exe = std::env::current_exe().ok();
        self.in_steam = self.overrides.self_added || self.steam.shortcuts().iter().any(|s| Some(&s.exe) == exe.as_ref());
        self.tools = self.steam.lepton_tools();
    }

    fn check_connection(&mut self) {
        self.spawn_quiet(|| Msg::Connected(SteamClient::reachable()));
    }

    fn game(&self, appid: u32) -> Option<&Game> {
        self.games.iter().find(|g| g.appid == appid)
    }

    fn tool_name(&self, id: Option<&str>) -> String {
        match id {
            None => "not set".into(),
            Some(id) => self.tools.iter().find(|t| t.id == id).map_or_else(|| id.to_string(), |t| t.name.clone()),
        }
    }

    fn push(&mut self, screen: Screen) {
        self.stack.push(screen);
        self.focus_first = true;
    }

    fn back(&mut self) {
        if self.stack.len() > 1 {
            self.stack.pop();
        }
        self.focus_first = true;
    }

    fn reset_to(&mut self, screen: Screen) {
        self.stack.truncate(1);
        if !matches!(screen, Screen::Home) {
            self.stack.push(screen);
        }
        self.focus_first = true;
    }

    fn spawn(&mut self, label: &str, job: impl FnOnce() -> Msg + Send + 'static) {
        self.busy = Some(label.to_string());
        self.spawn_quiet(job);
    }

    fn spawn_quiet(&self, job: impl FnOnce() -> Msg + Send + 'static) {
        let tx = self.tx.clone();
        let ctx = self.ctx.clone();
        std::thread::spawn(move || {
            let _ = tx.send(job());
            ctx.request_repaint();
        });
    }

    /// Runs a change through Steam's client API, asking for the one-time Steam setup first when needed.
    fn steam_change(&mut self, label: &str, done: &str, change: impl FnOnce() -> Result<(), String> + Send + 'static) {
        if self.connected != Some(true) {
            self.push(Screen::Connect);
            return;
        }
        let done = done.to_string();
        self.spawn(label, move || Msg::Done(change().map(|()| done)));
    }

    fn handle(&mut self, msg: Msg) {
        match msg {
            Msg::Connected(ok) => self.connected = Some(ok),
            Msg::Done(result) => {
                self.busy = None;
                self.status = Some(match result {
                    Ok(text) => (text, false),
                    Err(e) => (e, true),
                });
                self.refresh();
            }
            Msg::Packages(appid, packages) => {
                self.packages.insert(appid, packages);
            }
            Msg::Gsf(appid, id) => {
                self.gsf.insert(appid, id);
            }
            Msg::Added(result) => {
                self.busy = None;
                match result {
                    Ok((appid, name, exe, tool)) => {
                        let slot = lepton::is_slot(&exe);
                        self.overrides.added.push(Game {
                            appid,
                            name,
                            exe,
                            tool: Some(tool),
                            slot,
                            package: None,
                            play_store_next: false,
                        });
                        self.refresh();
                        self.reset_to(Screen::Added(appid, slot));
                    }
                    Err(e) => self.status = Some((format!("Couldn't add the game: {e}"), true)),
                }
            }
            Msg::GridGames(result) => {
                self.busy = None;
                match result {
                    Ok(games) => self.grid_games = games,
                    Err(e) => self.status = Some((e, true)),
                }
            }
            Msg::GridImages(result) => {
                self.busy = None;
                match result {
                    Ok(images) => self.grid_images = images,
                    Err(e) => self.status = Some((e, true)),
                }
            }
            Msg::Thumb(key, image) => {
                if let Some(image) = image {
                    let texture = self.ctx.load_texture(&key, image, TextureOptions::LINEAR);
                    self.textures.insert(key, texture);
                }
            }
            Msg::TaskLine(line) => self.task_log.push(line),
            Msg::TaskEnd(ok) => {
                self.task_running = false;
                self.task_log.push(if ok { "Finished.".into() } else { "Failed; see the messages above.".into() });
                self.refresh();
            }
        }
    }

    fn thumbnail(&mut self, ui: &mut egui::Ui, key: &str, load: impl FnOnce() -> Option<Vec<u8>> + Send + 'static) -> Option<TextureHandle> {
        if let Some(texture) = self.textures.get(key) {
            return Some(texture.clone());
        }
        if self.thumbs_requested.insert(key.to_string()) {
            let key = key.to_string();
            self.spawn_quiet(move || Msg::Thumb(key, load().and_then(|bytes| decode_thumb(&bytes))));
        }
        ui.ctx().request_repaint_after(Duration::from_millis(200));
        None
    }

    fn run_task(&mut self, title: &str, program: &str, args: Vec<String>) {
        self.task_log.clear();
        self.task_running = true;
        self.push(Screen::Task(title.to_string()));
        let tx = self.tx.clone();
        let ctx = self.ctx.clone();
        let mut command = Command::new(program);
        command.args(args).stdin(Stdio::null()).stdout(Stdio::piped()).stderr(Stdio::piped());
        std::thread::spawn(move || {
            let ok = match command.spawn() {
                Err(e) => {
                    let _ = tx.send(Msg::TaskLine(format!("Couldn't start: {e}")));
                    false
                }
                Ok(mut child) => {
                    let stderr = child.stderr.take().map(|err| {
                        let tx = tx.clone();
                        let ctx = ctx.clone();
                        std::thread::spawn(move || {
                            for line in BufReader::new(err).lines().map_while(Result::ok) {
                                let _ = tx.send(Msg::TaskLine(line));
                                ctx.request_repaint();
                            }
                        })
                    });
                    if let Some(out) = child.stdout.take() {
                        for line in BufReader::new(out).lines().map_while(Result::ok) {
                            let _ = tx.send(Msg::TaskLine(line));
                            ctx.request_repaint();
                        }
                    }
                    if let Some(handle) = stderr {
                        let _ = handle.join();
                    }
                    child.wait().is_ok_and(|s| s.success())
                }
            };
            let _ = tx.send(Msg::TaskEnd(ok));
            ctx.request_repaint();
        });
    }
}

impl eframe::App for App {
    fn raw_input_hook(&mut self, _ctx: &Context, raw_input: &mut egui::RawInput) {
        self.pad.feed(raw_input);
    }

    fn ui(&mut self, ui: &mut egui::Ui, _frame: &mut eframe::Frame) {
        let ctx = &ui.ctx().clone();
        while let Ok(msg) = self.rx.try_recv() {
            self.handle(msg);
        }
        ctx.request_repaint_after(Duration::from_millis(50));
        let navigating = ctx.input(|i| {
            [Key::ArrowUp, Key::ArrowDown, Key::ArrowLeft, Key::ArrowRight, Key::Enter].iter().any(|k| i.key_pressed(*k))
        });
        if self.busy.is_none() {
            if ctx.input(|i| i.key_pressed(Key::Escape)) && !ctx.egui_wants_keyboard_input() {
                self.back();
            } else if navigating && ctx.memory(|m| m.focused()).is_none() {
                self.focus_first = true;
            }
        }
        egui::CentralPanel::default().show(ui, |ui| {
            ui.add_enabled_ui(self.busy.is_none(), |ui| self.show(ui));
            if let Some(label) = &self.busy {
                let rect = ui.max_rect();
                ui.painter().rect_filled(rect, 0.0, Color32::from_black_alpha(160));
                ui.painter().text(rect.center(), Align2::CENTER_CENTER, format!("{label}…"), FontId::proportional(30.0), Color32::WHITE);
            }
        });
    }
}

impl App {
    fn show(&mut self, ui: &mut egui::Ui) {
        let screen = self.stack.last().cloned().unwrap_or(Screen::Home);
        let title = self.title(&screen);
        self.first_widget = true;
        ui.horizontal(|ui| {
            ui.heading(RichText::new(title).size(34.0).strong());
            ui.with_layout(egui::Layout::right_to_left(Align::Center), |ui| {
                ui.label(RichText::new("A  select     B  back").color(DIM));
            });
        });
        if let Some((text, error)) = &self.status {
            ui.label(RichText::new(text).color(if *error { DANGER } else { ACCENT }));
        }
        ui.add_space(8.0);
        ScrollArea::vertical().auto_shrink([false, false]).show(ui, |ui| match screen {
            Screen::Home => self.home(ui),
            Screen::Game(appid) => self.game_screen(ui, appid),
            Screen::ChangeGame(appid) => self.change_game(ui, appid),
            Screen::Rename(appid, name) => self.rename(ui, appid, name),
            Screen::Runtime(appid) => self.runtime(ui, appid),
            Screen::Artwork(appid) => self.artwork(ui, appid),
            Screen::ArtworkSource(appid, kind) => self.artwork_source(ui, appid, kind),
            Screen::LocalImages(appid, kind) => self.local_images(ui, appid, kind),
            Screen::GridGames(appid, kind) => self.grid_games_screen(ui, appid, kind),
            Screen::GridImages(appid, kind) => self.grid_images_screen(ui, appid, kind),
            Screen::Remove(appid) => self.remove(ui, appid),
            Screen::AddSource => self.add_source(ui),
            Screen::AddFile => self.add_file(ui),
            Screen::AddName(source, name) => self.add_name(ui, source, name),
            Screen::AddRuntime(source, name) => self.add_runtime(ui, source, name),
            Screen::Added(appid, slot) => self.added(ui, appid, slot),
            Screen::Connect => self.connect(ui),
            Screen::Settings(key) => self.settings(ui, key),
            Screen::Task(_) => self.task(ui),
        });
    }

    fn title(&self, screen: &Screen) -> String {
        let name = |appid: &u32| self.game(*appid).map_or_else(String::new, |g| g.name.clone());
        match screen {
            Screen::Home => "Lepton Game Manager".into(),
            Screen::Game(id) | Screen::Remove(id) => name(id),
            Screen::ChangeGame(id) => format!("{}: game", name(id)),
            Screen::Rename(id, _) => format!("{}: name", name(id)),
            Screen::Runtime(id) => format!("{}: runtime", name(id)),
            Screen::Artwork(id)
            | Screen::ArtworkSource(id, _)
            | Screen::LocalImages(id, _)
            | Screen::GridGames(id, _)
            | Screen::GridImages(id, _) => format!("{}: artwork", name(id)),
            Screen::AddSource | Screen::AddFile | Screen::AddName(..) | Screen::AddRuntime(..) => "Add a game".into(),
            Screen::Added(id, _) => format!("{} added", name(id)),
            Screen::Connect => "Connect to Steam".into(),
            Screen::Settings(_) => "Settings".into(),
            Screen::Task(title) => title.clone(),
        }
    }

    /// A full-width, focusable row; the first row of a screen takes focus when the screen opens.
    fn row(&mut self, ui: &mut egui::Ui, text: &str, detail: &str) -> bool {
        self.row_coloured(ui, text, detail, Color32::WHITE)
    }

    fn row_coloured(&mut self, ui: &mut egui::Ui, text: &str, detail: &str, colour: Color32) -> bool {
        let (rect, response) = ui.allocate_exact_size(vec2(ui.available_width(), 58.0), Sense::click());
        response.widget_info(|| egui::WidgetInfo::labeled(egui::Role::Button, true, text));
        self.take_first_focus(&response);
        if response.gained_focus() {
            response.scroll_to_me(Some(Align::Center));
        }
        let focused = ui.ctx().memory(|m| m.has_focus(response.id)) || response.hovered();
        let painter = ui.painter();
        painter.rect_filled(rect, 10.0, if focused { ACCENT.gamma_multiply(0.85) } else { Color32::from_rgb(34, 46, 62) });
        let left = rect.left_center() + vec2(18.0, 0.0);
        painter.text(left, Align2::LEFT_CENTER, text, FontId::proportional(24.0), colour);
        painter.text(rect.right_center() - vec2(18.0, 0.0), Align2::RIGHT_CENTER, detail, FontId::proportional(20.0), if focused { Color32::WHITE } else { DIM });
        ui.add_space(6.0);
        response.clicked()
    }

    /// The first focusable widget drawn takes focus until it has it (a request can be lost to a discarded pass).
    fn take_first_focus(&mut self, response: &egui::Response) {
        if !std::mem::take(&mut self.first_widget) || !self.focus_first {
            return;
        }
        response.request_focus();
        if response.ctx.memory(|m| m.has_focus(response.id)) {
            self.focus_first = false;
        }
    }

    fn section(ui: &mut egui::Ui, text: &str) {
        ui.add_space(10.0);
        ui.label(RichText::new(text).size(20.0).color(DIM));
        ui.add_space(4.0);
    }

    fn note(ui: &mut egui::Ui, text: &str) {
        ui.label(RichText::new(text).size(20.0).color(DIM));
        ui.add_space(6.0);
    }

    fn home(&mut self, ui: &mut egui::Ui) {
        Self::section(ui, "Games");
        for game in self.games.clone() {
            let detail = format!("{} · {}", game_target(&game), self.tool_name(game.tool.as_deref()));
            if self.row(ui, &game.name, &detail) {
                self.packages.remove(&game.appid);
                self.push(Screen::Game(game.appid));
            }
        }
        if self.row_coloured(ui, "+ Add a game", "", ACCENT.gamma_multiply(1.4)) {
            self.push(Screen::AddSource);
        }
        Self::section(ui, "Runtimes");
        if self.tools.is_empty() {
            Self::note(ui, "No Lepton runtime is installed: run the installer from Desktop Mode.");
        }
        for tool in self.tools.clone() {
            let detail = format!("{}{}", tool.bundle, if tool.gapps { " · Google Play" } else { "" });
            self.row(ui, &tool.name, &detail);
        }
        Self::section(ui, "Tools");
        let steam = match self.connected {
            Some(true) => "connected",
            Some(false) => "not connected",
            None => "checking",
        };
        if self.row(ui, "Steam connection", steam) {
            self.push(Screen::Connect);
        }
        if !self.in_steam && self.row(ui, "Add Lepton Game Manager to Steam", "to open it from Gaming Mode") {
            match std::env::current_exe() {
                Ok(exe) => {
                    self.overrides.self_added = true;
                    self.steam_change("Adding to Steam", "Added: it's under Non-Steam in your library", move || {
                        SteamClient::add_shortcut("Lepton Game Manager", &exe, None).map(drop)
                    });
                }
                Err(e) => self.status = Some((e.to_string(), true)),
            }
        }
        if self.row(ui, "Update Lepton + Padmap", "git pull and reinstall") {
            let update = self.repo.join("deck/update.sh").to_string_lossy().into_owned();
            self.run_task("Update", "bash", vec![update]);
        }
        if self.row(ui, "Save crash report", "to the Desktop") {
            let cli = home().join(".local/bin/lepton-padmap").to_string_lossy().into_owned();
            self.run_task("Crash report", &cli, vec!["report".into()]);
        }
        if self.row(ui, "Settings", "") {
            self.push(Screen::Settings(self.griddb_key.clone()));
        }
        if self.row(ui, "Quit", "") {
            ui.ctx().send_viewport_cmd(egui::ViewportCommand::Close);
        }
    }

    fn game_screen(&mut self, ui: &mut egui::Ui, appid: u32) {
        let Some(game) = self.game(appid).cloned() else {
            self.back();
            return;
        };
        let compat = self.steam.compatdata(appid);
        if self.row(ui, "Play", "") {
            self.steam_change("Starting", "Started", move || SteamClient::run(appid));
        }
        if game.slot {
            if self.row(ui, "Game", &game_target(&game)) {
                let compat = compat.clone();
                self.spawn_quiet(move || Msg::Packages(appid, lepton::installed_packages(&compat)));
                self.push(Screen::ChangeGame(appid));
            }
        } else {
            let file = game.exe.file_name().map(|f| f.to_string_lossy().into_owned()).unwrap_or_default();
            self.row(ui, "Game file", &file);
        }
        if self.row(ui, "Name", &game.name) {
            self.push(Screen::Rename(appid, game.name.clone()));
        }
        if self.row(ui, "Runtime", &self.tool_name(game.tool.as_deref())) {
            self.push(Screen::Runtime(appid));
        }
        if self.row(ui, "Artwork", "capsule, hero, logo, icon") {
            self.push(Screen::Artwork(appid));
        }
        let play_store = if game.play_store_next { "on" } else { "off" };
        if self.row(ui, "Open the Play Store on next launch", play_store) {
            let result = lepton::request_play_store(&compat, !game.play_store_next).map_err(|e| e.to_string());
            self.status = Some(match result {
                Ok(()) => ("Saved".into(), false),
                Err(e) => (e, true),
            });
            self.refresh();
        }
        if let Some(tool) = game.tool.as_deref().and_then(|id| self.tools.iter().find(|t| t.id == id)).cloned() {
            match self.gsf.get(&appid).cloned() {
                None => {
                    self.gsf.insert(appid, None);
                    let compat = compat.clone();
                    self.spawn_quiet(move || Msg::Gsf(appid, lepton::gsf_id(&tool, &compat)));
                }
                Some(Some(id)) => {
                    self.row(ui, "Google device ID", &id);
                    Self::note(ui, "If Google says this device isn't certified, register this ID at google.com/android/uncertified.");
                }
                Some(None) => {}
            }
        }
        if self.row_coloured(ui, "Remove", "", DANGER) {
            self.push(Screen::Remove(appid));
        }
    }

    fn change_game(&mut self, ui: &mut egui::Ui, appid: u32) {
        let compat = self.steam.compatdata(appid);
        let current = lepton::launch_package(&compat);
        if self.row(ui, "Pick in the Play Store", "on next launch") {
            let result = lepton::request_play_store(&compat, true);
            self.finish_local(result, "Next launch opens the Play Store; the app you install last becomes the game");
            self.back();
            return;
        }
        Self::section(ui, "Installed apps");
        match self.packages.get(&appid).cloned() {
            None => Self::note(ui, "Looking for installed apps…"),
            Some(packages) if packages.is_empty() => Self::note(ui, "Nothing is installed in this game's Android yet."),
            Some(packages) => {
                for package in packages {
                    let detail = if current.as_deref() == Some(package.as_str()) { "current" } else { "" };
                    if self.row(ui, &package, detail) {
                        let result = lepton::set_launch_package(&compat, &package).and_then(|()| lepton::request_play_store(&compat, false));
                        self.finish_local(result, "Saved");
                        self.back();
                        return;
                    }
                }
            }
        }
    }

    fn finish_local(&mut self, result: std::io::Result<()>, done: &str) {
        self.status = Some(match result {
            Ok(()) => (done.to_string(), false),
            Err(e) => (e.to_string(), true),
        });
        self.refresh();
    }

    fn text_field(&mut self, ui: &mut egui::Ui, value: &mut String) -> bool {
        let response = ui.add(egui::TextEdit::singleline(value).font(FontId::proportional(26.0)).desired_width(f32::INFINITY));
        self.take_first_focus(&response);
        Self::note(ui, "Steam + X opens the on-screen keyboard.");
        response.lost_focus() && ui.input(|i| i.key_pressed(Key::Enter))
    }

    fn rename(&mut self, ui: &mut egui::Ui, appid: u32, mut name: String) {
        let submitted = self.text_field(ui, &mut name);
        if let Some(Screen::Rename(_, buffer)) = self.stack.last_mut() {
            buffer.clone_from(&name);
        }
        if (self.row(ui, "Save", "") || submitted) && !name.trim().is_empty() {
            let name = name.trim().to_string();
            self.overrides.names.insert(appid, name.clone());
            self.steam_change("Renaming", "Renamed", move || SteamClient::rename(appid, &name));
            self.back();
        }
    }

    fn runtime(&mut self, ui: &mut egui::Ui, appid: u32) {
        let current = self.game(appid).and_then(|g| g.tool.clone());
        for tool in self.tools.clone() {
            let detail = if current.as_deref() == Some(tool.id.as_str()) { "current" } else { tool.bundle.as_str() };
            if self.row(ui, &tool.name, detail) {
                self.overrides.tools.insert(appid, tool.id.clone());
                let id = tool.id.clone();
                self.steam_change("Switching runtime", "Runtime changed", move || SteamClient::set_tool(appid, &id));
                self.back();
                return;
            }
        }
        Self::note(ui, "A different Android build may make Lepton reinstall the game; sign-in and saves are kept.");
    }

    fn artwork(&mut self, ui: &mut egui::Ui, appid: u32) {
        for (label, detail, kind) in [
            ("Capsule", "portrait library tile", Some(Artwork::Capsule)),
            ("Header", "landscape tile", Some(Artwork::Header)),
            ("Hero", "background banner", Some(Artwork::Hero)),
            ("Logo", "shown over the hero", Some(Artwork::Logo)),
            ("Icon", "", None),
        ] {
            if self.row(ui, label, detail) {
                self.push(Screen::ArtworkSource(appid, kind));
            }
        }
    }

    fn artwork_source(&mut self, ui: &mut egui::Ui, appid: u32, kind: Option<Artwork>) {
        if self.griddb_key.is_empty() {
            if self.row(ui, "Search SteamGridDB", "needs an API key in Settings") {
                self.push(Screen::Settings(String::new()));
            }
        } else if self.row(ui, "Search SteamGridDB", "") {
            let name = self.game(appid).map(|g| g.name.clone()).unwrap_or_default();
            let griddb = GridDb::new(&self.griddb_key);
            self.grid_games.clear();
            self.spawn("Searching", move || Msg::GridGames(griddb.search(&name)));
            self.push(Screen::GridGames(appid, kind));
        }
        if self.row(ui, "Pick an image file", "Pictures, Downloads, Desktop") {
            self.push(Screen::LocalImages(appid, kind));
        }
    }

    fn local_images(&mut self, ui: &mut egui::Ui, appid: u32, kind: Option<Artwork>) {
        let files = image_files();
        if files.is_empty() {
            Self::note(ui, "No .png or .jpg files in Pictures, Downloads or Desktop.");
            return;
        }
        let mut picked = None;
        ui.horizontal_wrapped(|ui| {
            for file in files {
                let path = file.clone();
                let texture = self.thumbnail(ui, &file.to_string_lossy(), move || std::fs::read(path).ok());
                if self.image_button(ui, texture, &file.file_name().unwrap_or_default().to_string_lossy()) {
                    picked = Some(file);
                }
            }
        });
        if let Some(file) = picked {
            self.apply_artwork(appid, kind, ArtSource::File(file));
        }
    }

    fn grid_games_screen(&mut self, ui: &mut egui::Ui, appid: u32, kind: Option<Artwork>) {
        if self.grid_games.is_empty() {
            Self::note(ui, "No matches on SteamGridDB.");
        }
        for (id, name) in self.grid_games.clone() {
            if self.row(ui, &name, "") {
                let griddb = GridDb::new(&self.griddb_key);
                self.grid_images.clear();
                self.spawn("Loading artwork", move || Msg::GridImages(griddb.images(id, kind)));
                self.push(Screen::GridImages(appid, kind));
            }
        }
    }

    fn grid_images_screen(&mut self, ui: &mut egui::Ui, appid: u32, kind: Option<Artwork>) {
        if self.grid_images.is_empty() {
            Self::note(ui, "No artwork of this kind for this game.");
        }
        let mut picked = None;
        ui.horizontal_wrapped(|ui| {
            for image in self.grid_images.clone() {
                let griddb = GridDb::new(&self.griddb_key);
                let thumb = image.thumb.clone();
                let texture = self.thumbnail(ui, &image.thumb, move || griddb.download(&thumb).ok());
                if self.image_button(ui, texture, "") {
                    picked = Some(image.url.clone());
                }
            }
        });
        if let Some(url) = picked {
            self.apply_artwork(appid, kind, ArtSource::Url(url, GridDb::new(&self.griddb_key)));
        }
    }

    fn image_button(&mut self, ui: &mut egui::Ui, texture: Option<TextureHandle>, caption: &str) -> bool {
        let size = vec2(THUMB, THUMB);
        let response = match &texture {
            Some(texture) => ui.add(egui::Button::image(egui::Image::new(texture).max_size(size)).min_size(size)),
            None => ui.add(egui::Button::new(if caption.is_empty() { "…" } else { caption }).min_size(size)),
        };
        self.take_first_focus(&response);
        if response.gained_focus() {
            response.scroll_to_me(Some(Align::Center));
        }
        response.clicked()
    }

    fn apply_artwork(&mut self, appid: u32, kind: Option<Artwork>, source: ArtSource) {
        self.steam_change("Applying artwork", "Artwork updated", move || {
            let bytes = match &source {
                ArtSource::File(file) => std::fs::read(file).map_err(|e| e.to_string())?,
                ArtSource::Url(url, griddb) => griddb.download(url)?,
            };
            match kind {
                Some(kind) => SteamClient::set_artwork(appid, &bytes, kind),
                None => {
                    let icon = match &source {
                        ArtSource::File(file) => file.clone(),
                        ArtSource::Url(..) => {
                            let dir = home().join(".local/share/lepton-padmap/icons");
                            std::fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
                            let file = dir.join(format!("{appid}.png"));
                            std::fs::write(&file, &bytes).map_err(|e| e.to_string())?;
                            file
                        }
                    };
                    SteamClient::set_icon(appid, &icon)
                }
            }
        });
        self.stack.retain(|s| !matches!(s, Screen::ArtworkSource(..) | Screen::LocalImages(..) | Screen::GridGames(..) | Screen::GridImages(..)));
        self.focus_first = true;
    }

    fn remove(&mut self, ui: &mut egui::Ui, appid: u32) {
        Self::note(ui, "Removing the shortcut keeps the game's Android data unless you delete it too; adding the same game with the same name again picks the data back up.");
        if self.row(ui, "Remove from Steam", "keep game data") {
            self.overrides.removed.insert(appid);
            self.steam_change("Removing", "Removed", move || SteamClient::remove(appid));
            self.reset_to(Screen::Home);
            return;
        }
        if self.row_coloured(ui, "Remove and delete game data", "sign-in, saves, installed apps", DANGER) {
            self.overrides.removed.insert(appid);
            let compat = self.steam.compatdata(appid);
            self.steam_change("Removing", "Removed", move || {
                SteamClient::remove(appid)?;
                lepton::delete_profile(&compat).map_err(|e| e.to_string())
            });
            self.reset_to(Screen::Home);
            return;
        }
        if self.row(ui, "Cancel", "") {
            self.back();
        }
    }

    fn add_source(&mut self, ui: &mut egui::Ui) {
        if self.row(ui, "From Google Play", "sign in and install in the Play Store") {
            self.push(Screen::AddName(Source::Play, String::new()));
        }
        if self.row(ui, "From a game file", ".apk or .apkm") {
            self.push(Screen::AddFile);
        }
    }

    fn add_file(&mut self, ui: &mut egui::Ui) {
        let files = game_files();
        if files.is_empty() {
            Self::note(ui, "No .apk or .apkm files in Downloads, Desktop or your home folder.");
        }
        for file in files {
            let name = file.file_stem().unwrap_or_default().to_string_lossy().into_owned();
            let dir = file.parent().map(|d| d.to_string_lossy().into_owned()).unwrap_or_default();
            if self.row(ui, &name, &dir) {
                self.push(Screen::AddName(Source::File(file), name));
            }
        }
    }

    fn add_name(&mut self, ui: &mut egui::Ui, source: Source, mut name: String) {
        Self::note(ui, "Name shown in Steam:");
        let submitted = self.text_field(ui, &mut name);
        if let Some(Screen::AddName(_, buffer)) = self.stack.last_mut() {
            buffer.clone_from(&name);
        }
        if (self.row(ui, "Next", "") || submitted) && !name.trim().is_empty() {
            self.push(Screen::AddRuntime(source, name.trim().to_string()));
        }
    }

    fn add_runtime(&mut self, ui: &mut egui::Ui, source: Source, name: String) {
        let tools: Vec<Tool> = self.tools.iter().filter(|t| t.gapps || source != Source::Play).cloned().collect();
        if tools.is_empty() {
            Self::note(ui, "No Lepton runtime with Google Play is installed.");
        }
        for tool in tools {
            if self.row(ui, &tool.name, &tool.bundle) {
                if self.connected != Some(true) {
                    self.push(Screen::Connect);
                    return;
                }
                let source = source.clone();
                let name = name.clone();
                self.spawn("Adding to Steam", move || {
                    Msg::Added((|| {
                        let exe = match source {
                            Source::Play => lepton::new_slot(&name).map_err(|e| e.to_string())?,
                            Source::File(file) => file,
                        };
                        let appid = SteamClient::add_shortcut(&name, &exe, Some(&tool.id))?;
                        Ok((appid, name, exe, tool.id))
                    })())
                });
            }
        }
    }

    fn added(&mut self, ui: &mut egui::Ui, appid: u32, slot: bool) {
        Self::note(
            ui,
            if slot {
                "It's in your library. On its first launch the Play Store opens: sign in, install the game, then quit. \
                 The app you install becomes this shortcut's game."
            } else {
                "It's in your library. The first launch installs the game into its own Android."
            },
        );
        Self::note(ui, "In its controller settings, turn on Touchscreen Native Support so screen taps reach the game.");
        if self.row(ui, "Play now", "") {
            self.steam_change("Starting", "Started", move || SteamClient::run(appid));
        }
        if self.row(ui, "Done", "") {
            self.reset_to(Screen::Home);
        }
    }

    fn connect(&mut self, ui: &mut egui::Ui) {
        let enabled = SteamClient::enable_file(&self.steam.root).is_file();
        match (self.connected, enabled) {
            (Some(true), _) => Self::note(ui, "Connected: changes apply to Steam right away."),
            (_, false) => Self::note(
                ui,
                "The manager changes your Steam library through Steam's local debugging port, as Decky plugins do. \
                 Allow it once, then restart Steam (or the Deck).",
            ),
            (_, true) => Self::note(ui, "Allowed. Restart Steam (or the Deck) once so Steam opens the port, then check again."),
        }
        if !enabled && self.row(ui, "Allow", "one-time") {
            let file = SteamClient::enable_file(&self.steam.root);
            let result = std::fs::write(&file, b"");
            self.finish_local(result, "Allowed: restart Steam once");
        }
        if self.row(ui, "Check again", "") {
            self.connected = None;
            self.spawn("Checking", || Msg::Connected(SteamClient::reachable()));
        }
    }

    fn settings(&mut self, ui: &mut egui::Ui, mut key: String) {
        Self::note(ui, "SteamGridDB API key (optional, for artwork search; steamgriddb.com > Preferences > API):");
        let submitted = self.text_field(ui, &mut key);
        if let Some(Screen::Settings(buffer)) = self.stack.last_mut() {
            buffer.clone_from(&key);
        }
        if self.row(ui, "Save", "") || submitted {
            self.griddb_key = key.trim().to_string();
            let result = settings_write(&self.griddb_key);
            self.finish_local(result, "Saved");
            self.back();
        }
    }

    fn task(&mut self, ui: &mut egui::Ui) {
        for line in &self.task_log {
            ui.label(RichText::new(line).monospace().size(16.0));
        }
        if !self.task_running && self.row(ui, "Close", "") {
            self.back();
        }
        if self.task_running {
            ui.scroll_to_cursor(Some(Align::BOTTOM));
        }
    }
}

enum ArtSource {
    File(PathBuf),
    Url(String, GridDb),
}

fn game_target(game: &Game) -> String {
    match (&game.package, game.slot, game.play_store_next) {
        (_, _, true) => "Play Store on next launch".into(),
        (Some(package), true, _) => package.clone(),
        (None, true, _) => "pick in the Play Store".into(),
        (_, false, _) => game.exe.file_name().map(|f| f.to_string_lossy().into_owned()).unwrap_or_default(),
    }
}

fn decode_thumb(bytes: &[u8]) -> Option<ColorImage> {
    let image = image::load_from_memory(bytes).ok()?.thumbnail(THUMB as u32 * 2, THUMB as u32 * 2).to_rgba8();
    Some(ColorImage::from_rgba_unmultiplied([image.width() as usize, image.height() as usize], image.as_raw()))
}

fn files_with(dirs: &[PathBuf], extensions: &[&str], filter: impl Fn(&Path) -> bool) -> Vec<PathBuf> {
    let mut files: Vec<PathBuf> = dirs
        .iter()
        .flat_map(|dir| std::fs::read_dir(dir).into_iter().flatten().flatten())
        .map(|e| e.path())
        .filter(|p| p.is_file())
        .filter(|p| p.extension().and_then(|e| e.to_str()).is_some_and(|e| extensions.iter().any(|x| e.eq_ignore_ascii_case(x))))
        .filter(|p| filter(p))
        .collect();
    files.sort_by_key(|p| std::cmp::Reverse(std::fs::metadata(p).and_then(|m| m.modified()).ok()));
    files
}

fn image_files() -> Vec<PathBuf> {
    let home = home();
    files_with(&[home.join("Pictures"), home.join("Downloads"), home.join("Desktop")], &["png", "jpg", "jpeg"], |_| true)
}

fn game_files() -> Vec<PathBuf> {
    let home = home();
    files_with(&[home.join("Downloads"), home.join("Desktop"), home.clone()], &["apk", "apkm"], |p| !lepton::is_slot(p))
}

fn settings_path() -> PathBuf {
    home().join(".config/lepton-padmap/manager.json")
}

fn settings_read() -> String {
    let json: serde_json::Value =
        std::fs::read_to_string(settings_path()).ok().and_then(|s| serde_json::from_str(&s).ok()).unwrap_or_default();
    json["steamgriddb_key"].as_str().unwrap_or_default().to_string()
}

fn settings_write(key: &str) -> std::io::Result<()> {
    let path = settings_path();
    std::fs::create_dir_all(path.parent().unwrap_or(Path::new("/")))?;
    std::fs::write(path, serde_json::json!({ "steamgriddb_key": key }).to_string())
}

fn style(ctx: &Context) {
    ctx.all_styles_mut(|style| {
        style.visuals = egui::Visuals::dark();
        style.visuals.panel_fill = Color32::from_rgb(22, 30, 42);
        style.visuals.widgets.active.bg_fill = ACCENT;
        style.visuals.widgets.active.weak_bg_fill = ACCENT;
        style.visuals.widgets.active.bg_stroke = egui::Stroke::new(3.0, Color32::WHITE);
        style.visuals.selection.bg_fill = ACCENT.gamma_multiply(0.6);
        for (text_style, size) in
            [(egui::TextStyle::Body, 22.0), (egui::TextStyle::Button, 22.0), (egui::TextStyle::Heading, 34.0)]
        {
            style.text_styles.insert(text_style, FontId::proportional(size));
        }
        style.spacing.item_spacing = vec2(10.0, 8.0);
    });
}

#[cfg(test)]
mod tests {
    use super::*;
    use egui_kittest::Harness;
    use egui_kittest::kittest::Queryable;

    #[test]
    fn controller_navigation() {
        let (dir, steam) = crate::steam::tests::fixture();
        let mut harness =
            Harness::builder().with_size(vec2(1280.0, 800.0)).build_eframe(|cc| App::with_steam(cc, steam));
        let press = |harness: &mut Harness<'_, App>, key| {
            harness.key_press(key);
            harness.run_steps(3);
        };
        harness.run_steps(3);
        assert!(harness.get_by_label("UNITE").is_focused(), "the first game is focused when the manager opens");
        press(&mut harness, Key::ArrowDown);
        assert!(harness.get_by_label("+ Add a game").is_focused(), "down moves to the next row");
        press(&mut harness, Key::ArrowUp);
        press(&mut harness, Key::Enter);
        assert!(harness.get_by_label("Play").is_focused(), "A opens the game, focused on Play");
        assert!(harness.query_by_label("Game file").is_some(), "a game from a file shows its file");
        press(&mut harness, Key::Escape);
        assert!(harness.get_by_label("UNITE").is_focused(), "B goes back to the list");
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn add_a_play_game_asks_for_the_steam_connection_first() {
        let (dir, steam) = crate::steam::tests::fixture();
        let mut harness =
            Harness::builder().with_size(vec2(1280.0, 800.0)).build_eframe(|cc| App::with_steam(cc, steam));
        harness.run_steps(3);
        harness.state_mut().connected = Some(false);
        harness.get_by_label("+ Add a game").click();
        harness.run_steps(3);
        harness.get_by_label("From Google Play").click();
        harness.run_steps(3);
        harness.get_by_role(egui::Role::TextInput).type_text("Brawl");
        harness.run_steps(2);
        harness.get_by_label("Next").click();
        harness.run_steps(3);
        assert!(matches!(harness.state().stack.last(), Some(Screen::AddRuntime(Source::Play, name)) if name == "Brawl"));
        harness.get_by_label("Lepton + Padmap").click();
        harness.run_steps(3);
        assert!(matches!(harness.state().stack.last(), Some(Screen::Connect)), "no Steam connection: set it up first");
        harness.get_by_label("Allow").click();
        harness.run_steps(3);
        assert!(dir.join(".cef-enable-remote-debugging").is_file(), "Allow enables Steam's debugging port");
        std::fs::remove_dir_all(dir).unwrap();
    }
}
