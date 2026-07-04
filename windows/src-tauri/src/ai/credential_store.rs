/// Secure credential storage for the Claude API key and the local Scanmarker account
/// password gate. Uses the `keyring` crate which wraps:
///   - Windows Credential Manager on Windows
///   - macOS Keychain on macOS
///   - libsecret / kwallet on Linux
use keyring::Entry;
use sha2::{Digest, Sha256};

const SERVICE: &str = "com.topscan.ScanToExternApp";
const ACCOUNT: &str = "ClaudeAPIKey";
const SCANMARKER_PASSWORD_ACCOUNT: &str = "ScanmarkerPasswordHash";

pub fn save_api_key(key: &str) -> anyhow::Result<()> {
    let entry = Entry::new(SERVICE, ACCOUNT)?;
    entry.set_password(key)?;
    Ok(())
}

pub fn load_api_key() -> anyhow::Result<String> {
    let entry = Entry::new(SERVICE, ACCOUNT)?;
    Ok(entry.get_password()?)
}

#[allow(dead_code)]
pub fn delete_api_key() -> anyhow::Result<()> {
    let entry = Entry::new(SERVICE, ACCOUNT)?;
    entry.delete_credential()?;
    Ok(())
}

// ── Local Scanmarker account password ─────────────────────────────────────────────────
//
// This is NOT real authentication — Scanmarker's cloud OCR service only checks the email
// field, no password. This hash is a local-only gate so a user has to confirm "yes, it's
// me" before changing the Scanmarker email on this machine, mirroring Mac's
// KeychainManager.saveScanmarkerPasswordHash/verifyScanmarkerPassword. Losing it just
// means: set a new one next time, same as setting one for the first time — there's
// nothing to "recover."

fn sha256_hex(input: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(input.as_bytes());
    hasher
        .finalize()
        .iter()
        .map(|b| format!("{:02x}", b))
        .collect()
}

pub fn save_scanmarker_password(password: &str) -> anyhow::Result<()> {
    if password.is_empty() {
        return delete_scanmarker_password();
    }
    let entry = Entry::new(SERVICE, SCANMARKER_PASSWORD_ACCOUNT)?;
    entry.set_password(&sha256_hex(password))?;
    Ok(())
}

pub fn verify_scanmarker_password(password: &str) -> bool {
    let Ok(entry) = Entry::new(SERVICE, SCANMARKER_PASSWORD_ACCOUNT) else { return false };
    let Ok(stored_hex) = entry.get_password() else { return false };
    stored_hex == sha256_hex(password)
}

pub fn has_scanmarker_password() -> bool {
    let Ok(entry) = Entry::new(SERVICE, SCANMARKER_PASSWORD_ACCOUNT) else { return false };
    entry.get_password().is_ok()
}

fn delete_scanmarker_password() -> anyhow::Result<()> {
    let entry = Entry::new(SERVICE, SCANMARKER_PASSWORD_ACCOUNT)?;
    entry.delete_credential().ok();
    Ok(())
}
