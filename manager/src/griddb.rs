use crate::client::Artwork;
use serde_json::Value;
use std::time::Duration;

const API: &str = "https://www.steamgriddb.com/api/v2";

#[derive(Clone, Debug)]
pub struct Image {
    pub url: String,
    pub thumb: String,
}

pub struct GridDb {
    key: String,
    agent: ureq::Agent,
}

impl GridDb {
    pub fn new(key: &str) -> GridDb {
        let agent = ureq::Agent::config_builder().timeout_global(Some(Duration::from_secs(20))).build().new_agent();
        GridDb { key: key.to_string(), agent }
    }

    /// Games matching a name: (SteamGridDB game id, name).
    pub fn search(&self, term: &str) -> Result<Vec<(u64, String)>, String> {
        let data = self.get(&format!("{API}/search/autocomplete/{}", encode(term)))?;
        Ok(data
            .iter()
            .filter_map(|g| Some((g["id"].as_u64()?, g["name"].as_str()?.to_string())))
            .collect())
    }

    /// Artwork for a game; the icon kind is `None`.
    pub fn images(&self, game: u64, kind: Option<Artwork>) -> Result<Vec<Image>, String> {
        let query = match kind {
            Some(Artwork::Capsule) => "grids/game/{}?dimensions=600x900,342x482,660x930",
            Some(Artwork::Header) => "grids/game/{}?dimensions=460x215,920x430",
            Some(Artwork::Hero) => "heroes/game/{}",
            Some(Artwork::Logo) => "logos/game/{}",
            None => "icons/game/{}",
        };
        let data = self.get(&format!("{API}/{}", query.replace("{}", &game.to_string())))?;
        Ok(data
            .iter()
            .filter_map(|i| Some(Image { url: i["url"].as_str()?.to_string(), thumb: i["thumb"].as_str()?.to_string() }))
            .collect())
    }

    pub fn download(&self, url: &str) -> Result<Vec<u8>, String> {
        self.agent
            .get(url)
            .call()
            .map_err(|e| e.to_string())?
            .body_mut()
            .with_config()
            .limit(32 * 1024 * 1024)
            .read_to_vec()
            .map_err(|e| e.to_string())
    }

    fn get(&self, url: &str) -> Result<Vec<Value>, String> {
        let reply: Value = self
            .agent
            .get(url)
            .header("Authorization", &format!("Bearer {}", self.key))
            .call()
            .map_err(|e| match e {
                ureq::Error::StatusCode(401) => "SteamGridDB rejected the API key".to_string(),
                e => e.to_string(),
            })?
            .body_mut()
            .read_json()
            .map_err(|e| e.to_string())?;
        Ok(reply["data"].as_array().cloned().unwrap_or_default())
    }
}

fn encode(s: &str) -> String {
    s.bytes()
        .map(|b| match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'.' | b'_' | b'~' => (b as char).to_string(),
            _ => format!("%{b:02X}"),
        })
        .collect()
}

#[cfg(test)]
mod tests {
    #[test]
    fn encodes_search_terms() {
        assert_eq!(super::encode("Pokémon UNITE/2"), "Pok%C3%A9mon%20UNITE%2F2");
    }
}
