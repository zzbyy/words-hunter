use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use thiserror::Error;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppConfig {
    pub vault_path: String,
    pub template_path: String,
    pub hotkey: String,
    pub sound_enabled: bool,
    pub bubble_enabled: bool,
}

impl Default for AppConfig {
    fn default() -> Self {
        let vault_path = dirs::home_dir()
            .map(|p| p.join(".wordshunter").join("vault").to_string_lossy().to_string())
            .unwrap_or_default();
        let template_path = dirs::home_dir()
            .map(|p| p.join(".wordshunter").join("template.md").to_string_lossy().to_string())
            .unwrap_or_default();

        Self {
            vault_path,
            template_path,
            hotkey: "Alt+double-click".to_string(),
            sound_enabled: true,
            bubble_enabled: true,
        }
    }
}

fn config_path() -> PathBuf {
    dirs::home_dir()
        .unwrap_or_else(|| PathBuf::from("."))
        .join(".wordshunter")
        .join("config.json")
}

#[derive(Error, Debug)]
pub enum ConfigError {
    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),
    #[error("JSON error: {0}")]
    Json(#[from] serde_json::Error),
}

pub fn load_config() -> Option<AppConfig> {
    let path = config_path();
    if !path.exists() {
        return None;
    }
    let content = std::fs::read_to_string(&path).ok()?;
    serde_json::from_str(&content).ok()
}

pub fn save_config(config: &AppConfig) -> Result<(), ConfigError> {
    let path = config_path();
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    let content = serde_json::to_string_pretty(config)?;
    std::fs::write(path, content)?;
    Ok(())
}
