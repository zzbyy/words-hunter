use std::collections::BTreeMap;
use std::fs;
use std::path::PathBuf;

use serde::{Deserialize, Serialize};
use thiserror::Error;

// MARK: - v2 Types

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct SightingEvent {
    pub timestamp: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub channel: Option<String>,
    pub words: BTreeMap<String, String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct SightingsStore {
    pub version: u32,
    pub days: BTreeMap<String, Vec<SightingEvent>>,
}

// MARK: - v1 Types (migration only)

#[derive(Debug, Clone, Deserialize)]
struct SightingEntryV1 {
    date: String,
    sentence: String,
    channel: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
struct SightingsStoreV1 {
    version: u32,
    days: BTreeMap<String, BTreeMap<String, Vec<SightingEntryV1>>>,
}

// Version detection
#[derive(Debug, Deserialize)]
struct VersionOnly {
    version: u32,
}

#[derive(Error, Debug)]
pub enum SightingsError {
    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),
    #[error("JSON error: {0}")]
    Json(#[from] serde_json::Error),
}

// MARK: - Paths

pub fn sightings_path(vault_path: &str) -> PathBuf {
    PathBuf::from(vault_path)
        .join(".wordshunter")
        .join("sightings.json")
}

// MARK: - Read / Write

/// Read and decode the sightings store. Transparently migrates v1 → v2.
/// Returns None if the file is missing or has an unknown version.
pub fn read_sightings(vault_path: &str) -> Option<SightingsStore> {
    let path = sightings_path(vault_path);
    let content = fs::read_to_string(&path).ok()?;

    let version_info: VersionOnly = serde_json::from_str(&content).ok()?;

    match version_info.version {
        2 => serde_json::from_str(&content).ok(),
        1 => {
            let v1: SightingsStoreV1 = serde_json::from_str(&content).ok()?;
            Some(migrate_v1_to_v2(&v1))
        }
        _ => None,
    }
}

/// Write the store atomically via temp+rename. Auto-prunes days older than 30.
pub fn write_sightings(store: &SightingsStore, vault_path: &str) -> Result<(), SightingsError> {
    let mut pruned = store.clone();
    prune_old_days(&mut pruned);

    let path = sightings_path(vault_path);
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }

    let content = serde_json::to_string_pretty(&pruned)?;

    let tmp = path.with_file_name(format!(
        ".sightings-{}.json.tmp",
        std::process::id()
    ));
    fs::write(&tmp, &content)?;
    fs::rename(&tmp, &path)?;
    Ok(())
}

/// Record a single sighting.
pub fn record_sighting(
    vault_path: &str,
    word: &str,
    sentence: &str,
    channel: Option<&str>,
) -> Result<(), SightingsError> {
    let today = today_string();
    let mut words = BTreeMap::new();
    words.insert(word.to_lowercase(), sentence.to_string());

    let event = SightingEvent {
        timestamp: now_timestamp(),
        channel: channel.map(|s| s.to_string()),
        words,
    };

    let mut store = read_sightings(vault_path).unwrap_or(SightingsStore {
        version: 2,
        days: BTreeMap::new(),
    });

    store.days.entry(today).or_default().push(event);
    write_sightings(&store, vault_path)
}

// MARK: - Migration

/// Convert v1 store to v2 event-based format.
fn migrate_v1_to_v2(v1: &SightingsStoreV1) -> SightingsStore {
    let mut v2_days: BTreeMap<String, Vec<SightingEvent>> = BTreeMap::new();

    for (date, word_map) in &v1.days {
        // Group by channel to coalesce entries
        let mut channel_words: BTreeMap<Option<String>, BTreeMap<String, String>> = BTreeMap::new();
        for (word, entries) in word_map {
            for entry in entries {
                channel_words
                    .entry(entry.channel.clone())
                    .or_default()
                    .insert(word.clone(), entry.sentence.clone());
            }
        }
        let mut events = Vec::new();
        for (channel, words) in channel_words {
            events.push(SightingEvent {
                timestamp: format!("{}T00:00", date),
                channel,
                words,
            });
        }
        v2_days.insert(date.clone(), events);
    }

    SightingsStore {
        version: 2,
        days: v2_days,
    }
}

// MARK: - Pruning

/// Remove days older than 30 days from today.
fn prune_old_days(store: &mut SightingsStore) {
    let cutoff = chrono::Local::now()
        .date_naive()
        .checked_sub_days(chrono::Days::new(30));
    if let Some(cutoff_date) = cutoff {
        let cutoff_str = cutoff_date.format("%Y-%m-%d").to_string();
        store.days.retain(|date, _| date.as_str() >= cutoff_str.as_str());
    }
}

// MARK: - Helpers

fn today_string() -> String {
    chrono::Local::now().format("%Y-%m-%d").to_string()
}

fn now_timestamp() -> String {
    chrono::Local::now().format("%Y-%m-%dT%H:%M").to_string()
}

// MARK: - Tests

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    fn temp_vault() -> PathBuf {
        let dir = std::env::temp_dir().join(format!(
            "wh-test-{}-{}",
            std::process::id(),
            std::thread::current().id().as_u64()
        ));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(dir.join(".wordshunter")).unwrap();
        dir
    }

    fn cleanup(path: &PathBuf) {
        let _ = fs::remove_dir_all(path);
    }

    #[test]
    fn test_read_missing() {
        let vault = temp_vault();
        assert!(read_sightings(vault.to_str().unwrap()).is_none());
        cleanup(&vault);
    }

    #[test]
    fn test_round_trip() {
        let vault = temp_vault();
        let vp = vault.to_str().unwrap();

        let mut words = BTreeMap::new();
        words.insert("posit".to_string(), "I posit that this works.".to_string());

        let store = SightingsStore {
            version: 2,
            days: {
                let mut d = BTreeMap::new();
                d.insert("2026-04-04".to_string(), vec![SightingEvent {
                    timestamp: "2026-04-04T21:15".to_string(),
                    channel: Some("Telegram".to_string()),
                    words,
                }]);
                d
            },
        };
        write_sightings(&store, vp).unwrap();

        let loaded = read_sightings(vp).unwrap();
        assert_eq!(store, loaded);
        cleanup(&vault);
    }

    #[test]
    fn test_record_creates_file() {
        let vault = temp_vault();
        let vp = vault.to_str().unwrap();

        assert!(!sightings_path(vp).exists());
        record_sighting(vp, "deliberate", "", None).unwrap();
        assert!(sightings_path(vp).exists());

        let store = read_sightings(vp).unwrap();
        assert_eq!(store.version, 2);
        let today = today_string();
        assert_eq!(store.days[&today].len(), 1);
        assert!(store.days[&today][0].words.contains_key("deliberate"));
        cleanup(&vault);
    }

    #[test]
    fn test_record_appends_to_day() {
        let vault = temp_vault();
        let vp = vault.to_str().unwrap();

        record_sighting(vp, "posit", "", None).unwrap();
        record_sighting(vp, "deliberate", "", None).unwrap();

        let store = read_sightings(vp).unwrap();
        let today = today_string();
        assert_eq!(store.days[&today].len(), 2);
        cleanup(&vault);
    }

    #[test]
    fn test_channel_none_omitted() {
        let vault = temp_vault();
        let vp = vault.to_str().unwrap();

        record_sighting(vp, "test", "", None).unwrap();

        let content = fs::read_to_string(sightings_path(vp)).unwrap();
        assert!(!content.contains("\"channel\""));
        cleanup(&vault);
    }

    #[test]
    fn test_migrate_v1_to_v2() {
        let vault = temp_vault();
        let vp = vault.to_str().unwrap();

        // Write v1 JSON directly
        let v1_json = r#"{
            "version": 1,
            "days": {
                "2026-04-04": {
                    "posit": [{"date": "2026-04-04", "sentence": "I posit this.", "channel": "Telegram"}],
                    "deliberate": [{"date": "2026-04-04", "sentence": "Be deliberate.", "channel": "Telegram"}]
                }
            }
        }"#;
        let path = sightings_path(vp);
        fs::write(&path, v1_json).unwrap();

        let store = read_sightings(vp).unwrap();
        assert_eq!(store.version, 2);
        let events = &store.days["2026-04-04"];
        // Both words had same channel, so coalesced into one event
        assert_eq!(events.len(), 1);
        assert_eq!(events[0].timestamp, "2026-04-04T00:00");
        assert_eq!(events[0].words.len(), 2);
        assert!(events[0].words.contains_key("posit"));
        assert!(events[0].words.contains_key("deliberate"));
        cleanup(&vault);
    }

    #[test]
    fn test_prune_old_days() {
        let vault = temp_vault();
        let vp = vault.to_str().unwrap();

        let mut store = SightingsStore {
            version: 2,
            days: BTreeMap::new(),
        };
        // Add an old day (60 days ago) and today
        let old_date = (chrono::Local::now() - chrono::Duration::days(60))
            .format("%Y-%m-%d")
            .to_string();
        let today = today_string();

        store.days.insert(old_date.clone(), vec![SightingEvent {
            timestamp: format!("{}T10:00", old_date),
            channel: None,
            words: {
                let mut w = BTreeMap::new();
                w.insert("old".to_string(), "".to_string());
                w
            },
        }]);
        store.days.insert(today.clone(), vec![SightingEvent {
            timestamp: format!("{}T10:00", today),
            channel: None,
            words: {
                let mut w = BTreeMap::new();
                w.insert("new".to_string(), "".to_string());
                w
            },
        }]);

        write_sightings(&store, vp).unwrap();
        let loaded = read_sightings(vp).unwrap();
        assert!(!loaded.days.contains_key(&old_date), "Old day should be pruned");
        assert!(loaded.days.contains_key(&today), "Today should be kept");
        cleanup(&vault);
    }
}
