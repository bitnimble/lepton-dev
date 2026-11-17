use crate::vdf::{self, Map};
use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};

pub struct Steam {
    pub root: PathBuf,
    user: Option<PathBuf>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Shortcut {
    pub appid: u32,
    pub name: String,
    pub exe: PathBuf,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Tool {
    pub id: String,
    pub name: String,
    /// The install's root: compat_tool/, tools/ and BUNDLE.json live here.
    pub root: PathBuf,
    pub bundle: String,
    pub gapps: bool,
}

impl Steam {
    pub fn locate() -> Steam {
        let home = home();
        let root = std::env::var_os("LEPTON_STEAM_DIR").map(PathBuf::from).unwrap_or_else(|| {
            let local = home.join(".local/share/Steam");
            if local.is_dir() { local } else { home.join(".steam/steam") }
        });
        let user = current_user(&root);
        Steam { root, user }
    }

    pub fn compatdata(&self, appid: u32) -> PathBuf {
        self.root.join("steamapps/compatdata").join(appid.to_string())
    }

    pub fn shortcuts(&self) -> Vec<Shortcut> {
        let Some(user) = &self.user else { return Vec::new() };
        let Ok(data) = fs::read(user.join("config/shortcuts.vdf")) else { return Vec::new() };
        let Some(root) = vdf::parse_binary(&data) else { return Vec::new() };
        let Some(entries) = vdf::get(&root, "shortcuts").and_then(|v| v.map()) else { return Vec::new() };
        entries.values().filter_map(|v| v.map()).filter_map(shortcut).collect()
    }

    /// Compatibility tool per app id, as Steam last saved config.vdf.
    pub fn tool_mapping(&self) -> HashMap<u32, String> {
        let text = fs::read_to_string(self.root.join("config/config.vdf")).unwrap_or_default();
        let Some(root) = vdf::parse_text(&text) else { return HashMap::new() };
        let keys = ["InstallConfigStore", "Software", "Valve", "Steam", "CompatToolMapping"];
        let Some(mapping) = vdf::path(&root, &keys).and_then(|v| v.map()) else { return HashMap::new() };
        mapping
            .iter()
            .filter_map(|(appid, entry)| {
                let name = vdf::get(entry.map()?, "name")?.str()?;
                Some((appid.parse().ok()?, name.to_string()))
            })
            .filter(|(_, name): &(u32, String)| !name.is_empty())
            .collect()
    }

    /// Installed Lepton tools registered with Steam.
    pub fn lepton_tools(&self) -> Vec<Tool> {
        let dir = self.root.join("compatibilitytools.d");
        let Ok(entries) = fs::read_dir(&dir) else { return Vec::new() };
        let mut files: Vec<PathBuf> = entries
            .flatten()
            .map(|e| e.path())
            .flat_map(|p| if p.is_dir() { vec![p.join("compatibilitytool.vdf")] } else { vec![p] })
            .filter(|p| p.extension().is_some_and(|e| e == "vdf") && p.is_file())
            .collect();
        files.sort();
        let mut tools: Vec<Tool> = files.iter().flat_map(|f| tools_in(f)).collect();
        tools.sort_by(|a, b| a.name.cmp(&b.name));
        tools
    }
}

pub fn home() -> PathBuf {
    std::env::var_os("HOME").map(PathBuf::from).unwrap_or_else(|| PathBuf::from("/"))
}

fn current_user(root: &Path) -> Option<PathBuf> {
    let userdata = root.join("userdata");
    let text = fs::read_to_string(root.join("config/loginusers.vdf")).unwrap_or_default();
    let recent = vdf::parse_text(&text).and_then(|root| {
        let users = vdf::get(&root, "users")?.map()?;
        users.iter().find_map(|(id, user)| {
            let most_recent = vdf::get(user.map()?, "MostRecent")?.str()? == "1";
            let steamid: u64 = id.parse().ok()?;
            most_recent.then(|| (steamid & 0xffff_ffff).to_string())
        })
    });
    if let Some(account) = recent {
        let dir = userdata.join(account);
        if dir.is_dir() {
            return Some(dir);
        }
    }
    let mut users: Vec<PathBuf> = fs::read_dir(&userdata)
        .ok()?
        .flatten()
        .map(|e| e.path())
        .filter(|p| p.is_dir() && p.file_name().and_then(|n| n.to_str()).is_some_and(|n| n.parse::<u64>().is_ok_and(|id| id > 0)))
        .collect();
    users.sort_by_key(|p| fs::metadata(p.join("config/shortcuts.vdf")).and_then(|m| m.modified()).ok());
    users.pop()
}

fn shortcut(entry: &Map) -> Option<Shortcut> {
    let appid = vdf::get(entry, "appid")?.int()? as u32;
    let name = vdf::get(entry, "AppName")?.str()?.to_string();
    let exe = vdf::get(entry, "Exe")?.str()?.trim_matches('"').to_string();
    Some(Shortcut { appid, name, exe: PathBuf::from(exe) })
}

fn tools_in(file: &Path) -> Vec<Tool> {
    let text = fs::read_to_string(file).unwrap_or_default();
    let Some(root) = vdf::parse_text(&text) else { return Vec::new() };
    let Some(tools) = vdf::path(&root, &["compatibilitytools", "compat_tools"]).and_then(|v| v.map()) else {
        return Vec::new();
    };
    let base = file.parent().unwrap_or(Path::new("/"));
    tools
        .iter()
        .filter_map(|(id, tool)| {
            let tool = tool.map()?;
            let install = base.join(vdf::get(tool, "install_path")?.str()?);
            if !install.join("lepton-x86_64-entry").is_file() {
                return None;
            }
            let root = install.parent()?.to_path_buf();
            let bundle: serde_json::Value = fs::read_to_string(root.join("BUNDLE.json"))
                .ok()
                .and_then(|s| serde_json::from_str(&s).ok())
                .unwrap_or_default();
            Some(Tool {
                id: id.clone(),
                name: vdf::get(tool, "display_name").and_then(|v| v.str()).unwrap_or(id).to_string(),
                root,
                bundle: bundle["bundle_id"].as_str().unwrap_or_default().to_string(),
                gapps: bundle["gapps"].as_bool().unwrap_or(false),
            })
        })
        .collect()
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;
    use crate::vdf::tests::binary_shortcut;

    /// A Steam directory with two shortcuts (UNITE, a Lepton game, and Firefox) and the lepton_padmap tool.
    pub(crate) fn fixture() -> (PathBuf, Steam) {
        let dir = std::env::temp_dir().join(format!("lepton-manager-test-{}-{:?}", std::process::id(), std::thread::current().id()));
        let _ = fs::remove_dir_all(&dir);
        let user = dir.join("userdata/12345");
        fs::create_dir_all(user.join("config")).unwrap();
        fs::create_dir_all(dir.join("config")).unwrap();
        fs::write(
            dir.join("config/loginusers.vdf"),
            "\"users\" { \"76561197960278073\" { \"AccountName\" \"deck\" \"MostRecent\" \"1\" } }",
        )
        .unwrap();
        let mut data = b"\x00shortcuts\0".to_vec();
        data.extend(binary_shortcut(0, 0xB676_0000u32 as i32, "UNITE", "\"/home/deck/unite.apkm\""));
        data.extend(binary_shortcut(1, 0x8000_0001u32 as i32, "Firefox", "\"/usr/bin/firefox\""));
        data.extend_from_slice(b"\x08\x08");
        fs::write(user.join("config/shortcuts.vdf"), data).unwrap();
        fs::write(
            dir.join("config/config.vdf"),
            "\"InstallConfigStore\" { \"Software\" { \"Valve\" { \"Steam\" { \"CompatToolMapping\" { \"3061187584\" { \"name\" \"lepton_padmap\" } \"7\" { \"name\" \"\" } } } } } }",
        )
        .unwrap();
        let tool = dir.join("tools/lepton_padmap");
        fs::create_dir_all(tool.join("compat_tool")).unwrap();
        fs::write(tool.join("compat_tool/lepton-x86_64-entry"), "").unwrap();
        fs::write(tool.join("BUNDLE.json"), r#"{"bundle_id": "auto-v0.2.0-alpha-r14-1", "gapps": true}"#).unwrap();
        fs::create_dir_all(dir.join("compatibilitytools.d")).unwrap();
        fs::write(
            dir.join("compatibilitytools.d/lepton_padmap.vdf"),
            format!(
                "\"compatibilitytools\" {{ \"compat_tools\" {{ \"lepton_padmap\" {{ \"install_path\" \"{}\" \"display_name\" \"Lepton + Padmap\" }} }} }}",
                tool.join("compat_tool").display()
            ),
        )
        .unwrap();
        fs::write(
            dir.join("compatibilitytools.d/proton.vdf"),
            "\"compatibilitytools\" { \"compat_tools\" { \"proton\" { \"install_path\" \".\" } } }",
        )
        .unwrap();
        let steam = Steam { user: current_user(&dir), root: dir.clone() };
        (dir, steam)
    }

    #[test]
    fn reads_shortcuts_mapping_and_tools() {
        let (dir, steam) = fixture();
        assert_eq!(steam.user, Some(dir.join("userdata/12345")));
        let shortcuts = steam.shortcuts();
        assert_eq!(shortcuts.len(), 2);
        assert_eq!(shortcuts[0].appid, 0xB676_0000);
        assert_eq!(shortcuts[0].name, "UNITE");
        assert_eq!(shortcuts[0].exe, PathBuf::from("/home/deck/unite.apkm"));
        assert_eq!(steam.tool_mapping(), HashMap::from([(3_061_187_584, "lepton_padmap".to_string())]));
        let tools = steam.lepton_tools();
        assert_eq!(tools.len(), 1);
        assert_eq!(tools[0].id, "lepton_padmap");
        assert_eq!(tools[0].name, "Lepton + Padmap");
        assert_eq!(tools[0].bundle, "auto-v0.2.0-alpha-r14-1");
        assert!(tools[0].gapps);
        fs::remove_dir_all(dir).unwrap();
    }
}
