use eframe::egui::{Context, Event, Key, Modifiers, RawInput};
use gilrs::{Axis, Button, EventType, Gilrs};
use std::sync::mpsc::{Receiver, Sender, channel};
use std::time::{Duration, Instant};

const STICK_THRESHOLD: f32 = 0.6;
const REPEAT_DELAY: Duration = Duration::from_millis(400);
const REPEAT_EVERY: Duration = Duration::from_millis(120);

/// Turns controller input into the keys egui already navigates with: arrows move focus (repeating while held),
/// Enter activates, Escape goes back.
pub struct Pad {
    keys: Receiver<Key>,
    /// Under gamescope the app on screen gets the pad; on a desktop, only a focused window should react to it.
    gamescope: bool,
}

impl Pad {
    pub fn new(ctx: &Context) -> Pad {
        let (tx, keys) = channel();
        let ctx = ctx.clone();
        std::thread::spawn(move || {
            if let Ok(gilrs) = Gilrs::new() {
                poll(gilrs, &tx, &ctx);
            }
        });
        Pad { keys, gamescope: std::env::var_os("GAMESCOPE_WAYLAND_DISPLAY").is_some() }
    }

    pub fn feed(&mut self, input: &mut RawInput) {
        let keys: Vec<Key> = self.keys.try_iter().collect();
        if keys.is_empty() || !(input.focused || self.gamescope) {
            return;
        }
        // egui only takes keys while it thinks the window has keyboard focus
        input.focused = true;
        for key in keys {
            for pressed in [true, false] {
                input.events.push(Event::Key { key, physical_key: None, pressed, repeat: false, modifiers: Modifiers::NONE });
            }
        }
    }
}

fn poll(mut gilrs: Gilrs, tx: &Sender<Key>, ctx: &Context) {
    let mut held: Option<(Key, Instant)> = None;
    let mut stick = (0i8, 0i8);
    loop {
        let timeout = held.map(|(_, at)| at.saturating_duration_since(Instant::now()));
        let send = |key| {
            let _ = tx.send(key);
            ctx.request_repaint();
        };
        let Some(event) = gilrs.next_event_blocking(timeout) else {
            if let Some((key, at)) = &mut held
                && Instant::now() >= *at
            {
                send(*key);
                *at = Instant::now() + REPEAT_EVERY;
            }
            continue;
        };
        match event.event {
            EventType::ButtonPressed(button, _) => {
                let Some(key) = key(button) else { continue };
                send(key);
                if is_arrow(key) {
                    held = Some((key, Instant::now() + REPEAT_DELAY));
                }
            }
            EventType::ButtonReleased(button, _) => {
                if held.is_some_and(|(key, _)| Some(key) == self::key(button)) {
                    held = None;
                }
            }
            EventType::AxisChanged(axis @ (Axis::LeftStickX | Axis::LeftStickY), value, _) => {
                let dir = if value > STICK_THRESHOLD { 1 } else if value < -STICK_THRESHOLD { -1 } else { 0 };
                let (slot, keys) = if axis == Axis::LeftStickX {
                    (&mut stick.0, (Key::ArrowLeft, Key::ArrowRight))
                } else {
                    (&mut stick.1, (Key::ArrowDown, Key::ArrowUp))
                };
                if dir == *slot {
                    continue;
                }
                *slot = dir;
                if dir == 0 {
                    held = None;
                } else {
                    let key = if dir < 0 { keys.0 } else { keys.1 };
                    send(key);
                    held = Some((key, Instant::now() + REPEAT_DELAY));
                }
            }
            _ => {}
        }
    }
}

fn is_arrow(key: Key) -> bool {
    matches!(key, Key::ArrowUp | Key::ArrowDown | Key::ArrowLeft | Key::ArrowRight)
}

fn key(button: Button) -> Option<Key> {
    Some(match button {
        Button::DPadUp => Key::ArrowUp,
        Button::DPadDown => Key::ArrowDown,
        Button::DPadLeft => Key::ArrowLeft,
        Button::DPadRight => Key::ArrowRight,
        Button::South => Key::Enter,
        Button::East => Key::Escape,
        _ => return None,
    })
}
