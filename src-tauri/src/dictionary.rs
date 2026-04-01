//! Dictionary lookup: Oxford Learner's Dictionary and Cambridge Dictionary.
//! Ported from CambridgeScraper.swift and OxfordScraper.swift.

use std::collections::HashMap;
use std::time::Duration;
use tracing::{info, debug, warn};
use thiserror::Error;

#[cfg(windows)]
use scraper::{Html, Selector};

#[derive(Error, Debug)]
pub enum DictionaryError {
    #[error("Network error: {0}")]
    Network(#[from] reqwest::Error),
    #[error("Parse error for {0}: {1}")]
    Parse(String, String),
    #[error("No definition found for {0}")]
    NotFound(String),
    #[error("Max retries exceeded")]
    MaxRetries,
}

#[derive(Default)]
pub struct LookupResult {
    pub pronunciation_bre: String,
    pub pronunciation_ame: String,
    pub cefr: String,
    pub meanings: String,
    pub corpus_examples: String,
    pub see_also: String,
    pub when_to_use: String,
    pub word_family: String,
}

impl LookupResult {
    pub fn into_vars(self) -> HashMap<&'static str, String> {
        let mut vars = HashMap::new();
        if !self.pronunciation_bre.is_empty() {
            vars.insert("{{pronunciation-bre}}", self.pronunciation_bre);
        }
        if !self.pronunciation_ame.is_empty() {
            vars.insert("{{pronunciation-ame}}", self.pronunciation_ame);
        }
        if !self.cefr.is_empty() {
            vars.insert("{{cefr}}", self.cefr);
        }
        if !self.meanings.is_empty() {
            vars.insert("{{meanings}}", self.meanings);
        }
        if !self.corpus_examples.is_empty() {
            vars.insert("{{corpus-examples}}", self.corpus_examples);
        }
        if !self.see_also.is_empty() {
            vars.insert("{{see-also}}", self.see_also);
        }
        if !self.when_to_use.is_empty() {
            vars.insert("{{when-to-use}}", self.when_to_use);
        }
        if !self.word_family.is_empty() {
            vars.insert("{{word-family}}", self.word_family);
        }
        vars
    }
}

/// Scrape Cambridge Dictionary for a word
#[cfg(windows)]
pub async fn lookup_cambridge(word: &str) -> Result<LookupResult, DictionaryError> {
    let url = format!(
        "https://dictionary.cambridge.org/dictionary/english/{}",
        word.to_lowercase().replace(' ', "-")
    );

    info!("Looking up Cambridge: {}", url);

    let client = reqwest::Client::builder()
        .user_agent("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")
        .timeout(Duration::from_secs(10))
        .build()?;

    let mut result = LookupResult::default();
    let mut retries = 0;
    let max_retries = 5;

    loop {
        match client.get(&url).send().await {
            Ok(response) => {
                if response.status() == reqwest::StatusCode::NOT_FOUND {
                    return Err(DictionaryError::NotFound(word.to_string()));
                }

                let body = response.text().await?;

                // Parse HTML with scraper (Rust equivalent of SwiftSoup)
                let document = Html::parse_document(&body);

                // Extract pronunciation (British)
                if let Some(pron) = extract_cambridge_pronunciation(&document, ".pron .ipa") {
                    result.pronunciation_bre = pron;
                }

                // Extract pronunciation (American) — look for US section
                if let Some(pron) = extract_cambridge_pronunciation(&document, ".us .pron .ipa") {
                    result.pronunciation_ame = pron;
                }

                // Extract CEFR level
                if let Some(cefr) = extract_cambridge_element(&document, ".freq") {
                    result.cefr = cefr.trim().to_string();
                }

                // Extract definitions
                if let Some(defs) = extract_cambridge_definitions(&document) {
                    result.meanings = defs;
                }

                // Extract examples
                if let Some(examples) = extract_cambridge_examples(&document) {
                    result.corpus_examples = examples;
                }

                // Extract word family
                if let Some(family) = extract_cambridge_word_family(&document) {
                    result.word_family = family;
                }

                break;
            }
            Err(e) => {
                retries += 1;
                if retries >= max_retries {
                    warn!("Cambridge lookup failed after {} retries: {:?}", retries, e);
                    return Err(DictionaryError::MaxRetries);
                }
                let backoff = Duration::from_millis(200 * (2_u64.pow(retries as u32)));
                debug!("Retry {} after {:?}ms", retries, backoff);
                tokio::time::sleep(backoff).await;
            }
        }
    }

    Ok(result)
}

#[cfg(windows)]
fn extract_cambridge_pronunciation(doc: &Html, selector_str: &str) -> Option<String> {
    let selector = Selector::parse(selector_str).ok()?;
    let element = doc.select(&selector).next()?;
    Some(element.text().collect::<String>().trim().to_string())
}

#[cfg(windows)]
fn extract_cambridge_element(doc: &Html, selector_str: &str) -> Option<String> {
    let selector = Selector::parse(selector_str).ok()?;
    let element = doc.select(&selector).next()?;
    Some(element.text().collect::<String>())
}

#[cfg(windows)]
fn extract_cambridge_definitions(doc: &Html) -> Option<String> {
    let selector = Selector::parse(".def-block").ok()?;
    let blocks: Vec<_> = doc.select(&selector).collect();
    if blocks.is_empty() {
        return None;
    }
    let mut output = String::new();
    for block in blocks.iter().take(5) {
        if let Some(d) = block.select(&Selector::parse(".def").ok()?).next() {
            let def_text = d.text().collect::<String>().trim().to_string();
            if !def_text.is_empty() {
                output.push_str(&format!("- {}\n", def_text));
            }
        }
    }
    Some(output.trim().to_string())
}

#[cfg(windows)]
fn extract_cambridge_examples(doc: &Html) -> Option<String> {
    let selector = Selector::parse(".def-block").ok()?;
    let blocks: Vec<_> = doc.select(&selector).collect();
    let mut examples = String::new();
    for block in blocks.iter().take(3) {
        if let Some(ex) = block.select(&Selector::parse(".examp .eg").ok()?).next() {
            let ex_text = ex.text().collect::<String>().trim().to_string();
            if !ex_text.is_empty() {
                examples.push_str(&format!("- {}\n", ex_text));
            }
        }
    }
    if examples.is_empty() {
        None
    } else {
        Some(examples.trim().to_string())
    }
}

#[cfg(windows)]
fn extract_cambridge_word_family(doc: &Html) -> Option<String> {
    let selector = Selector::parse(".word-family").ok()?;
    let elements: Vec<_> = doc.select(&selector).collect();
    if elements.is_empty() {
        return None;
    }
    let family = elements
        .iter()
        .map(|e| e.text().collect::<String>().trim().to_string())
        .collect::<Vec<_>>()
        .join(", ");
    Some(family)
}

/// Lookup Oxford Learner's Dictionary (fallback if Cambridge fails)
#[cfg(windows)]
pub async fn lookup_oxford(word: &str) -> Result<LookupResult, DictionaryError> {
    let url = format!(
        "https://www.oxfordlearnersdictionaries.com/definition/english/{}",
        word.to_lowercase().replace(' ', "-")
    );

    info!("Looking up Oxford: {}", url);

    let client = reqwest::Client::builder()
        .user_agent("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")
        .timeout(Duration::from_secs(10))
        .build()?;

    let response = client.get(&url).send().await?;

    if response.status() == reqwest::StatusCode::NOT_FOUND {
        return Err(DictionaryError::NotFound(word.to_string()));
    }

    let body = response.text().await?;
    let document = Html::parse_document(&body);

    let mut result = LookupResult::default();

    // Oxford uses slightly different selectors
    if let Some(pron) = extract_oxford_pronunciation(&document) {
        result.pronunciation_bre = pron;
    }

    if let Some(defs) = extract_oxford_definitions(&document) {
        result.meanings = defs;
    }

    Ok(result)
}

#[cfg(windows)]
fn extract_oxford_pronunciation(doc: &Html) -> Option<String> {
    let selector = Selector::parse(".phonetics .pron").ok()?;
    let element = doc.select(&selector).next()?;
    Some(element.text().collect::<String>().trim().to_string())
}

#[cfg(windows)]
fn extract_oxford_definitions(doc: &Html) -> Option<String> {
    let selector = Selector::parse(".sense").ok()?;
    let senses: Vec<_> = doc.select(&selector).collect();
    let mut output = String::new();
    for sense in senses.iter().take(5) {
        if let Some(def) = sense.select(&Selector::parse(".def").ok()?).next() {
            let text = def.text().collect::<String>().trim().to_string();
            if !text.is_empty() {
                output.push_str(&format!("- {}\n", text));
            }
        }
    }
    if output.is_empty() {
        None
    } else {
        Some(output.trim().to_string())
    }
}

/// Full lookup: try Cambridge first, fall back to Oxford
#[cfg(windows)]
pub async fn lookup_word(word: &str) -> Result<LookupResult, DictionaryError> {
    // Try Cambridge first
    match lookup_cambridge(word).await {
        Ok(mut result) => {
            // If Cambridge returned empty meanings, try Oxford
            if result.meanings.is_empty() {
                info!("Cambridge returned empty meanings, trying Oxford...");
                if let Ok(oxford) = lookup_oxford(word).await {
                    if !oxford.meanings.is_empty() {
                        result.meanings = oxford.meanings;
                    }
                    if oxford.pronunciation_bre.is_empty() {
                        result.pronunciation_bre = oxford.pronunciation_bre;
                    }
                }
            }
            Ok(result)
        }
        Err(e) => {
            debug!("Cambridge failed, trying Oxford: {:?}", e);
            lookup_oxford(word).await
        }
    }
}

#[cfg(not(windows))]
pub async fn lookup_word(_word: &str) -> Result<LookupResult, DictionaryError> {
    Ok(LookupResult::default())
}

#[cfg(not(windows))]
pub async fn lookup_cambridge(_word: &str) -> Result<LookupResult, DictionaryError> {
    Ok(LookupResult::default())
}

#[cfg(not(windows))]
pub async fn lookup_oxford(_word: &str) -> Result<LookupResult, DictionaryError> {
    Ok(LookupResult::default())
}
