use std::collections::BTreeMap;

#[derive(Debug, Clone, PartialEq)]
pub enum Value {
    Str(String),
    Int(i32),
    Map(Map),
}

pub type Map = BTreeMap<String, Value>;

impl Value {
    pub fn map(&self) -> Option<&Map> {
        match self {
            Value::Map(map) => Some(map),
            _ => None,
        }
    }

    pub fn str(&self) -> Option<&str> {
        match self {
            Value::Str(s) => Some(s),
            _ => None,
        }
    }

    pub fn int(&self) -> Option<i32> {
        match self {
            Value::Int(i) => Some(*i),
            _ => None,
        }
    }
}

/// Case-insensitive lookup: Steam writes the same key as `AppName`, `appname` or `appName` depending on version.
pub fn get<'a>(map: &'a Map, key: &str) -> Option<&'a Value> {
    map.iter().find(|(k, _)| k.eq_ignore_ascii_case(key)).map(|(_, v)| v)
}

pub fn path<'a>(map: &'a Map, keys: &[&str]) -> Option<&'a Value> {
    let (first, rest) = keys.split_first()?;
    let value = get(map, first)?;
    if rest.is_empty() {
        return Some(value);
    }
    path(value.map()?, rest)
}

/// Parses Steam's binary VDF (shortcuts.vdf).
pub fn parse_binary(data: &[u8]) -> Option<Map> {
    let mut pos = 0;
    let map = binary_map(data, &mut pos)?;
    Some(map)
}

fn binary_map(data: &[u8], pos: &mut usize) -> Option<Map> {
    let mut map = Map::new();
    loop {
        let kind = *data.get(*pos)?;
        *pos += 1;
        if kind == 0x08 {
            return Some(map);
        }
        let key = cstring(data, pos)?;
        let value = match kind {
            0x00 => Some(Value::Map(binary_map(data, pos)?)),
            0x01 => Some(Value::Str(cstring(data, pos)?)),
            0x02 => {
                let bytes = data.get(*pos..*pos + 4)?;
                *pos += 4;
                Some(Value::Int(i32::from_le_bytes(bytes.try_into().ok()?)))
            }
            // float, pointer, colour; uint64, int64: kept out of the map, nothing here reads them
            0x03 | 0x04 | 0x06 | 0x07 | 0x0A => {
                let size = if kind >= 0x07 { 8 } else { 4 };
                data.get(*pos..*pos + size)?;
                *pos += size;
                None
            }
            _ => return None,
        };
        if let Some(value) = value {
            map.insert(key, value);
        }
        if *pos == data.len() {
            return Some(map);
        }
    }
}

fn cstring(data: &[u8], pos: &mut usize) -> Option<String> {
    let end = *pos + data.get(*pos..)?.iter().position(|&b| b == 0)?;
    let s = String::from_utf8_lossy(&data[*pos..end]).into_owned();
    *pos = end + 1;
    Some(s)
}

/// Parses Steam's text VDF (config.vdf, loginusers.vdf, compatibilitytool .vdf files).
pub fn parse_text(text: &str) -> Option<Map> {
    let tokens = tokenize(text);
    let mut pos = 0;
    text_map(&tokens, &mut pos, true)
}

#[derive(Debug, PartialEq)]
enum Token {
    Str(String),
    Open,
    Close,
}

fn tokenize(text: &str) -> Vec<Token> {
    let mut tokens = Vec::new();
    let mut chars = text.chars().peekable();
    while let Some(c) = chars.next() {
        match c {
            '{' => tokens.push(Token::Open),
            '}' => tokens.push(Token::Close),
            '"' => {
                let mut s = String::new();
                while let Some(c) = chars.next() {
                    match c {
                        '"' => break,
                        '\\' => match chars.next() {
                            Some('n') => s.push('\n'),
                            Some('t') => s.push('\t'),
                            Some(other) => s.push(other),
                            None => break,
                        },
                        _ => s.push(c),
                    }
                }
                tokens.push(Token::Str(s));
            }
            '/' if chars.peek() == Some(&'/') => {
                for c in chars.by_ref() {
                    if c == '\n' {
                        break;
                    }
                }
            }
            c if c.is_whitespace() => {}
            c => {
                let mut s = String::from(c);
                while let Some(&next) = chars.peek() {
                    if next.is_whitespace() || next == '{' || next == '}' || next == '"' {
                        break;
                    }
                    s.push(next);
                    chars.next();
                }
                tokens.push(Token::Str(s));
            }
        }
    }
    tokens
}

fn text_map(tokens: &[Token], pos: &mut usize, top: bool) -> Option<Map> {
    let mut map = Map::new();
    loop {
        match tokens.get(*pos) {
            None if top => return Some(map),
            None => return None,
            Some(Token::Close) if !top => {
                *pos += 1;
                return Some(map);
            }
            Some(Token::Str(key)) => {
                *pos += 1;
                let value = match tokens.get(*pos)? {
                    Token::Str(s) => {
                        *pos += 1;
                        Value::Str(s.clone())
                    }
                    Token::Open => {
                        *pos += 1;
                        Value::Map(text_map(tokens, pos, false)?)
                    }
                    Token::Close => return None,
                };
                map.insert(key.clone(), value);
            }
            Some(_) => return None,
        }
    }
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;

    pub fn binary_shortcut(index: u32, appid: i32, name: &str, exe: &str) -> Vec<u8> {
        let mut out = vec![0x00];
        out.extend_from_slice(index.to_string().as_bytes());
        out.push(0);
        out.extend_from_slice(b"\x02appid\0");
        out.extend_from_slice(&appid.to_le_bytes());
        for (key, value) in [("AppName", name), ("Exe", exe), ("icon", "")] {
            out.push(0x01);
            out.extend_from_slice(key.as_bytes());
            out.push(0);
            out.extend_from_slice(value.as_bytes());
            out.push(0);
        }
        out.extend_from_slice(b"\x00tags\0\x08");
        out.extend_from_slice(b"\x07LastPlayTime64\0\x01\x02\x03\x04\x05\x06\x07\x08");
        out.push(0x08);
        out
    }

    #[test]
    fn binary_shortcuts() {
        let mut data = b"\x00shortcuts\0".to_vec();
        data.extend(binary_shortcut(0, -1_234_567, "UNITE", "\"/home/deck/unite.apkm\""));
        data.extend_from_slice(b"\x08\x08");
        let root = parse_binary(&data).unwrap();
        let entry = path(&root, &["shortcuts", "0"]).unwrap().map().unwrap();
        assert_eq!(get(entry, "appname").unwrap().str(), Some("UNITE"));
        assert_eq!(get(entry, "AppID").unwrap().int(), Some(-1_234_567));
        assert_eq!(get(entry, "exe").unwrap().str(), Some("\"/home/deck/unite.apkm\""));
    }

    #[test]
    fn text_config() {
        let text = r#"
"InstallConfigStore"
{
    "Software" { "Valve" { "Steam" {
        "CompatToolMapping"
        {
            "3061224960"  { "name"  "lepton_padmap" "config" "" "priority" "250" }
        }
    } } }
}"#;
        let root = parse_text(text).unwrap();
        let mapping = path(&root, &["InstallConfigStore", "Software", "Valve", "Steam", "CompatToolMapping"])
            .unwrap()
            .map()
            .unwrap();
        let entry = get(mapping, "3061224960").unwrap().map().unwrap();
        assert_eq!(get(entry, "name").unwrap().str(), Some("lepton_padmap"));
    }

    #[test]
    fn text_escapes_and_comments() {
        let root = parse_text("// c\n\"a\" { \"b\" \"x\\\"y\" }").unwrap();
        assert_eq!(path(&root, &["a", "b"]).unwrap().str(), Some("x\"y"));
    }
}
