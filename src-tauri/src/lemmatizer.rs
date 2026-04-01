//! Lemmatization using the navalp crate (pure Rust WordNet-based lemmatizer).
//! Translates words like "posited" -> "posit", "running" -> "run".

use navalp::{Lemmatizer, Config};
use once_cell::sync::Lazy;
use std::time::Instant;
use tracing::{debug, warn};

static LEMMATIZER: Lazy<Option<Lemmatizer>> = Lazy::new(|| {
    match Lemmatizer::new(Config::default()) {
        Ok(lemmatizer) => {
            info!("Lemmatizer initialized successfully");
            Some(lemmatizer)
        }
        Err(e) => {
            warn!("Failed to initialize lemmatizer: {:?}", e);
            None
        }
    }
});

/// Lemmatize a word. Returns the lemmatized form, or the original word if unavailable.
pub fn lemmatize(word: &str) -> String {
    let word_lower = word.to_lowercase();

    // Check navalp
    if let Some(ref lem) = *LEMMATIZER {
        let start = Instant::now();
        if let Some(lemma) = lem.lemmatize(&word_lower) {
            let elapsed = start.elapsed();
            debug!("Lemmatized '{}' -> '{}' in {:?}", word_lower, lemma, elapsed);
            if elapsed.as_millis() > 50 {
                warn!("Lemmatization took {:?} (>50ms target)", elapsed);
            }
            return lemma;
        }
    }

    // Fallback: strip common suffixes heuristically
    let fallback = heuristic_lemmatize(&word_lower);
    debug!("Using fallback lemmatization: '{}' -> '{}'", word_lower, fallback);
    fallback
}

/// Simple heuristic lemmatizer as fallback when navalp is unavailable.
fn heuristic_lemmatize(word: &str) -> String {
    // Handle common irregular forms
    match word {
        "ran" => "run".to_string(),
        "sat" => "sit".to_string(),
        "ate" => "eat".to_string(),
        "gone" => "go".to_string(),
        "written" => "write".to_string(),
        "wrote" => "write".to_string(),
        "spoken" => "speak".to_string(),
        "spoke" => "speak".to_string(),
        "ridden" => "ride".to_string(),
        "rode" => "ride".to_string(),
        "seen" => "see".to_string(),
        "saw" => "see".to_string(),
        "been" => "be".to_string(),
        "borne" => "bear".to_string(),
        "born" => "bear".to_string(),
        "taken" => "take".to_string(),
        "took" => "take".to_string(),
        "given" => "give".to_string(),
        "gave" => "give".to_string(),
        "forgotten" => "forget".to_string(),
        "forgot" => "forget".to_string(),
        _ => {
            // Strip common suffixes
            let suffixes = ["ing", "ed", "s", "es", "lier", "liest", "ness", "ment"];
            for suffix in &suffixes {
                if word.ends_with(suffix) && word.len() > suffix.len() + 2 {
                    let base = &word[..word.len() - suffix.len()];
                    // Don't strip if it would make the word too short
                    if base.len() >= 2 {
                        return base.to_string();
                    }
                }
            }
            word.to_string()
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_lemmatize() {
        assert_eq!(lemmatize("running"), "run");
        assert_eq!(lemmatize("posited"), "posit");
        assert_eq!(lemmatize("better"), "better"); // navalp may handle this
    }
}
