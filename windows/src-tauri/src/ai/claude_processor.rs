/// Claude API processor — cloud AI opt-in (user provides their own key).
/// Mirrors Mac's ClaudeProcessor.swift.
/// Model: claude-haiku-4-5 (fastest, cheapest — ideal for real-time scan processing).
use anyhow::Result;

const ANTHROPIC_URL: &str = "https://api.anthropic.com/v1/messages";
const MODEL: &str = "claude-haiku-4-5";

pub async fn process(
    text: &str,
    mode: &str,
    target_language: &str,
    api_key: &str,
) -> Result<String> {
    let instruction = match mode {
        "correct" => format!(
            "Fix any OCR errors, punctuation, and spacing in this scanned text. \
             Return only the corrected text, nothing else:\n\n{text}"
        ),
        "translate" => format!(
            "Translate this text to {target_language}. \
             Return only the translation, nothing else:\n\n{text}"
        ),
        "summarize" => format!("Summarize this in one sentence:\n\n{text}"),
        "custom" => text.to_string(), // caller should embed the custom instruction
        _ => return Ok(text.to_string()),
    };

    let client = reqwest::Client::new();

    let body = serde_json::json!({
        "model": MODEL,
        "max_tokens": 1024,
        "messages": [
            { "role": "user", "content": instruction }
        ]
    });

    let resp = client
        .post(ANTHROPIC_URL)
        .header("x-api-key", api_key)
        .header("anthropic-version", "2023-06-01")
        .header("content-type", "application/json")
        .json(&body)
        .send()
        .await?
        .error_for_status()?;

    let json: serde_json::Value = resp.json().await?;

    let result = json["content"]
        .as_array()
        .and_then(|arr| arr.first())
        .and_then(|item| item["text"].as_str())
        .ok_or_else(|| anyhow::anyhow!("Unexpected Claude API response shape"))?
        .to_string();

    log::debug!("[AI] Claude processed {} → {} chars", text.len(), result.len());
    Ok(result)
}
