use eframe::egui::{Event, Key, Modifiers, RawInput};
use gilrs::{Axis, Button, EventType, Gilrs};

const STICK_THRESHOLD: f32 = 0.6;

/// Turns controller input into the keys egui already navigates with: arrows move focus, Enter activates,
/// Escape goes back.
pub struct Pad {
    gilrs: Option<Gilrs>,
    stick: (i8, i8),
}

impl Pad {
    pub fn new() -> Pad {
        Pad { gilrs: Gilrs::new().ok(), stick: (0, 0) }
    }

    pub fn feed(&mut self, input: &mut RawInput) {
        let Some(gilrs) = &mut self.gilrs else { return };
        while let Some(event) = gilrs.next_event() {
            match event.event {
                EventType::ButtonPressed(button, _) | EventType::ButtonRepeated(button, _) => {
                    if let Some(key) = key(button) {
                        press(input, key);
                    }
                }
                EventType::AxisChanged(axis @ (Axis::LeftStickX | Axis::LeftStickY), value, _) => {
                    let dir = if value > STICK_THRESHOLD { 1 } else if value < -STICK_THRESHOLD { -1 } else { 0 };
                    let (slot, keys) = if axis == Axis::LeftStickX {
                        (&mut self.stick.0, (Key::ArrowLeft, Key::ArrowRight))
                    } else {
                        (&mut self.stick.1, (Key::ArrowDown, Key::ArrowUp))
                    };
                    if dir != *slot && dir != 0 {
                        press(input, if dir < 0 { keys.0 } else { keys.1 });
                    }
                    *slot = dir;
                }
                _ => {}
            }
        }
    }
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

fn press(input: &mut RawInput, key: Key) {
    // Pad input reaches us whether or not the window has keyboard focus, and egui ignores keys without it.
    input.focused = true;
    for pressed in [true, false] {
        input.events.push(Event::Key { key, physical_key: None, pressed, repeat: false, modifiers: Modifiers::NONE });
    }
}
