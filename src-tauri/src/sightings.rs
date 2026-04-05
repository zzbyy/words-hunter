use std::collections::BTreeMap;
use std::fs;
use std::path::PathBuf;
use std::thread;
use std::time::{Duration, SystemTime};

use serde::{Deserialize, Serialize};
use thiserror::Error;

// MARK: - Types

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct SightingEntry {
    pub date: String,
    pub sentence: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub channel: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct SightingsStore {
    pub version: u32,
    pub days: BTreeMap<String, BTreeMap<String, Vec<SightingEntry>>>,
}

#[derive(Error, Debug)]
pub enum SightingsError {
    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),
    #[error("JSON error: {0}")]
    Json(#[from] serde_json::Error),
    #[error("Failed to acquire lock after retries")]
    LockFailed,
}

// MARK: - Paths

pub fn sightings_path(vault_path: &str) -> PathBuf {
    PathBuf::from(vault_path)
        .join(".wordshunter")
        .join("sightings.json")
}

pub fn lock_path(vault_path: &str) -> PathBuf {
    PathBuf::from(vault_path)
        .join(".wordshunter")
        .join(".sightings.lock")
}

// MARK: - Read / Write

/// Read and decode the sightings store. Returns None if the file is missing or
/// has an unknown version.
pub fn read_sightings(vault_path: &str) -> Option<SightingsStore> {
    let path = sightings_path(vault_path);
    let content = fs::read_to_string(&path).ok()?;
    let store: SightingsStore = serde_json::from_str(&content).ok()?;
    if store.version != 1 {
        return None;
    }
    Some(store)
}

/// Write the store atomically via temp+rename.
pub fn write_sightings(store: &SightingsStore, vault_path: &str) -> Result<(), SightingsError> {
    let path = sightings_path(vault_path);
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }

    let content = serde_json::to_string_pretty(store)?;

    // Write to a temp file in the same directory, then atomic rename
    let tmp = path.with_file_name(format!(
        ".sightings-{}.json.tmp",
        std::process::id()
    ));
    fs::write(&tmp, &content)?;
    fs::rename(&tmp, &path)?;
    Ok(())
}

/// Record a single sighting with lock protection.
pub fn record_sighting(
    vault_path: &str,
    word: &str,
    sentence: &str,
    channel: Option<&str>,
) -> Result<(), SightingsError> {
    acquire_lock(vault_path)?;
    let result = record_sighting_inner(vault_path, word, sentence, channel);
    release_lock(vault_path);
    result
}

fn record_sighting_inner(
    vault_path: &str,
    word: &str,
    sentence: &str,
    channel: Option<&str>,
) -> Result<(), SightingsError> {
    let today = chrono::Local::now().format("%Y-%m-%d").to_string();
    let entry = SightingEntry {
        date: today.clone(),
        sentence: sentence.to_string(),
        channel: channel.map(|s| s.to_string()),
    };

    let mut store = read_sightings(vault_path).unwrap_or(SightingsStore {
        version: 1,
        days: BTreeMap::new(),
    });

    let key = word.to_lowercase();
    store
        .days
        .entry(today)
        .or_default()
        .entry(key)
        .or_default()
        .push(entry);

    write_sightings(&store, vault_path)
}

// MARK: - Locking (mkdir-based, compatible with proper-lockfile)

/// Acquire a lock by creating a directory. `mkdir` is atomic on POSIX — if the
/// directory already exists, `create_dir` returns an error, which we treat as
/// "lock held by another process".
fn acquire_lock(vault_path: &str) -> Result<(), SightingsError> {
    let lock = lock_path(vault_path);
    // Ensure parent exists
    if let Some(parent) = lock.parent() {
        fs::create_dir_all(parent)?;
    }

    for attempt in 0..10u32 {
        match fs::create_dir(&lock) {
            Ok(_) => return Ok(()),
            Err(_) => {
                // Check for stale lock (mtime > 10s ago)
                if let Ok(meta) = fs::metadata(&lock) {
                    if let Ok(modified) = meta.modified() {
                        if SystemTime::now()
                            .duration_since(modified)
                            .unwrap_or_default()
                            > Duration::from_secs(10)
                        {
                            let _ = fs::remove_dir_all(&lock);
                            continue; // retry immediately after stale removal
                        }
                    }
                }
                // Exponential backoff: 100ms * 2^attempt, capped at ~1.6s
                let delay = Duration::from_millis(100 * 2u64.pow(attempt)).min(Duration::from_millis(1600));
                thread::sleep(delay);
            }
        }
    }
    Err(SightingsError::LockFailed)
}

fn release_lock(vault_path: &str) {
    let _ = fs::remove_dir_all(lock_path(vault_path));
}

// MARK: - Tests

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    fn temp_vault() -> PathBuf {
        let dir = std::env::temp_dir().join(format!("wh-test-{}", std::process::id()));
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

        let mut days = BTreeMap::new();
        let mut words = BTreeMap::new();
        words.insert(
            "posit".to_string(),
            vec![SightingEntry {
                date: "2026-04-04".to_string(),
                sentence: "I posit that this works.".to_string(),
                channel: Some("telegram".to_string()),
            }],
        );
        days.insert("2026-04-04".to_string(), words);

        let store = SightingsStore { version: 1, days };
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
        record_sighting(vp, "deliberate", "She was deliberate in her actions.", None).unwrap();
        assert!(sightings_path(vp).exists());

        let store = read_sightings(vp).unwrap();
        assert_eq!(store.version, 1);
        // Should have one day with one word
        assert_eq!(store.days.values().next().unwrap().len(), 1);
        cleanup(&vault);
    }

    #[test]
    fn test_record_appends() {
        let vault = temp_vault();
        let vp = vault.to_str().unwrap();

        record_sighting(vp, "posit", "First sighting.", None).unwrap();
        record_sighting(vp, "posit", "Second sighting.", None).unwrap();

        let store = read_sightings(vp).unwrap();
        let today = chrono::Local::now().format("%Y-%m-%d").to_string();
        let entries = &store.days[&today]["posit"];
        assert_eq!(entries.len(), 2);
        assert_eq!(entries[0].sentence, "First sighting.");
        assert_eq!(entries[1].sentence, "Second sighting.");
        cleanup(&vault);
    }

    #[test]
    fn test_channel_none_omitted() {
        let vault = temp_vault();
        let vp = vault.to_str().unwrap();

        let store = SightingsStore {
            version: 1,
            days: {
                let mut d = BTreeMap::new();
                let mut w = BTreeMap::new();
                w.insert(
                    "test".to_string(),
                    vec![SightingEntry {
                        date: "2026-04-04".to_string(),
                        sentence: "test".to_string(),
                        channel: None,
                    }],
                );
                d.insert("2026-04-04".to_string(), w);
                d
            },
        };
        write_sightings(&store, vp).unwrap();

        let content = fs::read_to_string(sightings_path(vp)).unwrap();
        assert!(!content.contains("channel"));
        cleanup(&vault);
    }

    #[test]
    fn test_btreemap_sorted_keys() {
        let vault = temp_vault();
        let vp = vault.to_str().unwrap();

        record_sighting(vp, "zebra", "A zebra.", None).unwrap();
        record_sighting(vp, "apple", "An apple.", None).unwrap();

        let content = fs::read_to_string(sightings_path(vp)).unwrap();
        let apple_pos = content.find("apple").unwrap();
        let zebra_pos = content.find("zebra").unwrap();
        assert!(apple_pos < zebra_pos, "Keys should be sorted: apple before zebra");
        cleanup(&vault);
    }
}
