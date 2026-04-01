//! Obsidian vault integration: reads config, loads template,
//! creates {word}.md files with variable substitution.
//! Mirrors macOS WordPageCreator.swift behavior.

use std::path::{Path, PathBuf};
use std::fs;
use std::collections::HashMap;
use tracing::{info, debug, warn};
use thiserror::Error;

#[derive(Error, Debug)]
pub enum VaultError {
    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),
    #[error("Vault path not configured")]
    NoVaultPath,
    #[error("Template not found: {0}")]
    TemplateNotFound(String),
    #[error("Word file already exists: {0}")]
    AlreadyExists(String),
}

pub struct WordPage {
    pub word: String,
    pub date: String,
    pub lemma: String,
    pub pronunciation_bre: String,
    pub pronunciation_ame: String,
    pub meanings: String,
    pub cefr: String,
    pub corpus_examples: String,
    pub see_also: String,
    pub when_to_use: String,
    pub word_family: String,
}

impl Default for WordPage {
    fn default() -> Self {
        Self {
            word: String::new(),
            date: chrono::Local::now().format("%Y-%m-%d").to_string(),
            lemma: String::new(),
            pronunciation_bre: String::new(),
            pronunciation_ame: String::new(),
            meanings: String::new(),
            cefr: String::new(),
            corpus_examples: String::new(),
            see_also: String::new(),
            when_to_use: String::new(),
            word_family: String::new(),
        }
    }
}

/// Check if a word already exists in the vault
pub fn word_exists(vault_path: &str, word: &str) -> bool {
    let file_path = vault_path_to_file_path(vault_path, word);
    file_path.exists()
}

fn vault_path_to_file_path(vault_path: &str, word: &str) -> PathBuf {
    let safe_name = word.to_lowercase()
        .replace('/', "_")
        .replace('\\', "_")
        .replace(':', "_")
        .replace('*', "_")
        .replace('?', "_")
        .replace('"', "_")
        .replace('<', "_")
        .replace('>', "_")
        .replace('|', "_");
    PathBuf::from(vault_path).join(format!("{}.md", safe_name))
}

/// Load the template file
pub fn load_template(template_path: &str) -> Result<String, VaultError> {
    let path = Path::new(template_path);
    if !path.exists() {
        // Try default template
        let default = PathBuf::from(template_path);
        if default.exists() {
            return fs::read_to_string(&default).map_err(VaultError::Io);
        }
        return Err(VaultError::TemplateNotFound(template_path.to_string()));
    }
    fs::read_to_string(path).map_err(VaultError::Io)
}

/// Interpolate template variables: {{word}} -> value
pub fn interpolate_template(template: &str, page: &WordPage) -> String {
    let mut result = template.to_string();

    // Simple variable substitution — mirrors macOS WordPageUpdater
    let vars: HashMap<&str, &str> = HashMap::from([
        ("{{word}}", page.word.as_str()),
        ("{{date}}", page.date.as_str()),
        ("{{lemma}}", page.lemma.as_str()),
        ("{{pronunciation-bre}}", page.pronunciation_bre.as_str()),
        ("{{pronunciation-ame}}", page.pronunciation_ame.as_str()),
        ("{{meanings}}", page.meanings.as_str()),
        ("{{cefr}}", page.cefr.as_str()),
        ("{{corpus-examples}}", page.corpus_examples.as_str()),
        ("{{see-also}}", page.see_also.as_str()),
        ("{{when-to-use}}", page.when_to_use.as_str()),
        ("{{word-family}}", page.word_family.as_str()),
    ]);

    for (var, value) in vars {
        result = result.replace(var, value);
    }

    result
}

/// Create a word page file in the vault
pub fn create_word_page(
    vault_path: &str,
    template_path: &str,
    word: &str,
    lemma: &str,
    extra_vars: HashMap<&str, String>,
) -> Result<PathBuf, VaultError> {
    if word_exists(vault_path, word) {
        return Err(VaultError::AlreadyExists(word.to_string()));
    }

    let template = load_template(template_path)?;
    let mut page = WordPage::default();
    page.word = word.to_string();
    page.lemma = lemma.to_string();

    // Apply extra vars (from dictionary lookup)
    for (key, value) in extra_vars {
        match key {
            "{{pronunciation-bre}}" => page.pronunciation_bre = value,
            "{{pronunciation-ame}}" => page.pronunciation_ame = value,
            "{{meanings}}" => page.meanings = value,
            "{{cefr}}" => page.cefr = value,
            "{{corpus-examples}}" => page.corpus_examples = value,
            "{{see-also}}" => page.see_also = value,
            "{{when-to-use}}" => page.when_to_use = value,
            "{{word-family}}" => page.word_family = value,
            _ => {}
        }
    }

    let content = interpolate_template(&template, &page);
    let file_path = vault_path_to_file_path(vault_path, word);

    // Ensure vault directory exists
    if let Some(parent) = file_path.parent() {
        fs::create_dir_all(parent)?;
    }

    fs::write(&file_path, content)?;
    info!("Created word page: {:?}", file_path);

    Ok(file_path)
}

/// Update an existing word page with new data (e.g., dictionary lookups after creation)
pub fn update_word_page(
    vault_path: &str,
    word: &str,
    extra_vars: HashMap<&str, String>,
) -> Result<(), VaultError> {
    let file_path = vault_path_to_file_path(vault_path, word);
    if !file_path.exists() {
        warn!("Cannot update non-existent word page: {:?}", file_path);
        return Ok(()); // Not an error — just silently skip
    }

    let content = fs::read_to_string(&file_path)?;
    let mut page = WordPage::default();
    page.word = word.to_string();
    page.lemma = word.to_string();

    // Parse existing content to extract already-filled variables
    for (key, value) in extra_vars {
        match key {
            "{{pronunciation-bre}}" => page.pronunciation_bre = value,
            "{{pronunciation-ame}}" => page.pronunciation_ame = value,
            "{{meanings}}" => page.meanings = value,
            "{{cefr}}" => page.cefr = value,
            "{{corpus-examples}}" => page.corpus_examples = value,
            "{{see-also}}" => page.see_also = value,
            "{{when-to-use}}" => page.when_to_use = value,
            "{{word-family}}" => page.word_family = value,
            _ => {}
        }
    }

    let new_content = interpolate_template(&content, &page);
    fs::write(&file_path, new_content)?;
    debug!("Updated word page: {:?}", file_path);

    Ok(())
}
