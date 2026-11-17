use base64::Engine;
use serde_json::{Value, json};
use std::path::{Path, PathBuf};
use std::time::Duration;
use tungstenite::Message;

const DEBUGGER: &str = "http://127.0.0.1:8080/json";

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Artwork {
    Capsule = 0,
    Hero = 1,
    Logo = 2,
    Header = 3,
}

/// Steam's own client API (`SteamClient.Apps`, as Decky plugins use it), reached through Steam's
/// remote-debugging port; every change applies to the running Steam.
pub struct SteamClient;

impl SteamClient {
    /// The file that makes Steam open its debugging port on 127.0.0.1:8080 (read when Steam starts).
    pub fn enable_file(steam_root: &Path) -> PathBuf {
        steam_root.join(".cef-enable-remote-debugging")
    }

    pub fn reachable() -> bool {
        evaluate("1").is_ok()
    }

    /// Adds a non-Steam shortcut, run through `tool` when given.
    pub fn add_shortcut(name: &str, exe: &Path, tool: Option<&str>) -> Result<u32, String> {
        let dir = exe.parent().unwrap_or(Path::new("/"));
        let script = format!(
            "(async () => {{
                const id = await SteamClient.Apps.AddShortcut({name}, {exe}, {dir}, '');
                if (!id) throw new Error('Steam did not add the shortcut');
                await new Promise(r => setTimeout(r, 500));
                SteamClient.Apps.SetShortcutName(id, {name});
                {tool}
                return id;
            }})()",
            name = js(name),
            exe = js(&exe.to_string_lossy()),
            dir = js(&dir.to_string_lossy()),
            tool = tool.map_or_else(String::new, |tool| format!("SteamClient.Apps.SpecifyCompatTool(id, {});", js(tool))),
        );
        let id = evaluate(&script)?;
        id.as_u64().map(|id| id as u32).ok_or_else(|| format!("unexpected app id {id}"))
    }

    pub fn rename(appid: u32, name: &str) -> Result<(), String> {
        evaluate(&format!("SteamClient.Apps.SetShortcutName({appid}, {})", js(name))).map(drop)
    }

    pub fn set_tool(appid: u32, tool: &str) -> Result<(), String> {
        evaluate(&format!("SteamClient.Apps.SpecifyCompatTool({appid}, {})", js(tool))).map(drop)
    }

    pub fn set_icon(appid: u32, png: &Path) -> Result<(), String> {
        evaluate(&format!("SteamClient.Apps.SetShortcutIcon({appid}, {})", js(&png.to_string_lossy()))).map(drop)
    }

    pub fn set_artwork(appid: u32, image: &[u8], kind: Artwork) -> Result<(), String> {
        let format = if image.starts_with(b"\x89PNG") { "png" } else { "jpg" };
        let data = base64::engine::general_purpose::STANDARD.encode(image);
        let kind = kind as u8;
        evaluate(&format!("SteamClient.Apps.SetCustomArtworkForApp({appid}, '{data}', '{format}', {kind})")).map(drop)
    }

    pub fn remove(appid: u32) -> Result<(), String> {
        evaluate(&format!("SteamClient.Apps.RemoveShortcut({appid})")).map(drop)
    }

    pub fn run(appid: u32) -> Result<(), String> {
        let game_id = (u64::from(appid) << 32) | 0x0200_0000;
        evaluate(&format!("SteamClient.Apps.RunGame('{game_id}', '', -1, 100)")).map(drop)
    }
}

fn js(s: &str) -> String {
    Value::from(s).to_string()
}

fn evaluate(expression: &str) -> Result<Value, String> {
    evaluate_at(DEBUGGER, expression)
}

fn evaluate_at(debugger: &str, expression: &str) -> Result<Value, String> {
    let agent = ureq::Agent::config_builder().timeout_global(Some(Duration::from_secs(3))).build().new_agent();
    let targets: Value = agent
        .get(debugger)
        .call()
        .map_err(|e| format!("Steam isn't reachable on its debugging port: {e}"))?
        .body_mut()
        .read_json()
        .map_err(|e| e.to_string())?;
    let url = targets
        .as_array()
        .into_iter()
        .flatten()
        .find(|t| t["title"] == "SharedJSContext")
        .and_then(|t| t["webSocketDebuggerUrl"].as_str())
        .ok_or("Steam's client context isn't available yet")?;
    let (mut socket, _) = tungstenite::connect(url).map_err(|e| e.to_string())?;
    let request = json!({
        "id": 1,
        "method": "Runtime.evaluate",
        "params": { "expression": expression, "awaitPromise": true, "returnByValue": true },
    });
    socket.send(Message::text(request.to_string())).map_err(|e| e.to_string())?;
    loop {
        let message = socket.read().map_err(|e| e.to_string())?;
        let Message::Text(text) = message else { continue };
        let reply: Value = serde_json::from_str(&text).map_err(|e| e.to_string())?;
        if reply["id"] != 1 {
            continue;
        }
        let _ = socket.close(None);
        if let Some(details) = reply["result"].get("exceptionDetails") {
            let message = details["exception"]["description"].as_str().or(details["text"].as_str());
            return Err(message.unwrap_or("Steam reported an error").to_string());
        }
        return Ok(reply["result"]["result"]["value"].clone());
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::{Read, Write};
    use std::net::TcpListener;

    /// A stand-in for Steam's debugging port: the target list, then one websocket evaluate round trip.
    fn fake_steam(reply: Value) -> (String, std::thread::JoinHandle<Value>) {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let port = listener.local_addr().unwrap().port();
        let handle = std::thread::spawn(move || {
            let (mut http, _) = listener.accept().unwrap();
            let mut request = [0u8; 4096];
            let _ = http.read(&mut request).unwrap();
            let targets = json!([
                { "title": "Steam", "webSocketDebuggerUrl": format!("ws://127.0.0.1:{port}/devtools/page/other") },
                { "title": "SharedJSContext", "webSocketDebuggerUrl": format!("ws://127.0.0.1:{port}/devtools/page/shared") },
            ])
            .to_string();
            write!(http, "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{targets}", targets.len()).unwrap();
            drop(http);
            let (stream, _) = listener.accept().unwrap();
            let mut socket = tungstenite::accept(stream).unwrap();
            let request: Value = serde_json::from_str(socket.read().unwrap().to_text().unwrap()).unwrap();
            let mut reply = reply;
            reply["id"] = request["id"].clone();
            socket.send(Message::text(reply.to_string())).unwrap();
            let _ = socket.read();
            request
        });
        (format!("http://127.0.0.1:{port}/json"), handle)
    }

    #[test]
    fn evaluates_in_the_shared_context() {
        let (url, server) = fake_steam(json!({ "result": { "result": { "type": "number", "value": 2_734_686_208u32 } } }));
        assert_eq!(evaluate_at(&url, "SteamClient.Apps.AddShortcut()").unwrap(), json!(2_734_686_208u32));
        let request = server.join().unwrap();
        assert_eq!(request["method"], "Runtime.evaluate");
        assert_eq!(request["params"]["expression"], "SteamClient.Apps.AddShortcut()");
        assert_eq!(request["params"]["awaitPromise"], true);
    }

    #[test]
    fn reports_steam_exceptions() {
        let (url, server) = fake_steam(json!({ "result": {
            "result": { "type": "object" },
            "exceptionDetails": { "text": "Uncaught", "exception": { "description": "Error: Steam did not add the shortcut" } },
        } }));
        assert_eq!(evaluate_at(&url, "x").unwrap_err(), "Error: Steam did not add the shortcut");
        server.join().unwrap();
    }

    #[test]
    fn quotes_strings_for_javascript() {
        assert_eq!(js("O'Neil \"x\"\n"), r#""O'Neil \"x\"\n""#);
    }
}
