//! Lemmatization via heuristic suffix stripping.
//! Translates words like "posited" -> "posit", "running" -> "run".

use tracing::debug;

/// Lemmatize a word. Returns the base form, or the original word if no rule matches.
pub fn lemmatize(word: &str) -> String {
    let word_lower = word.to_lowercase();
    let result = heuristic_lemmatize(&word_lower);
    debug!("Lemmatized '{}' -> '{}'", word_lower, result);
    result
}

/// Simple heuristic lemmatizer based on common English suffix rules.
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
        assert_eq!(lemmatize("better"), "better");
    }
}
