/// Secure credential storage for the Claude API key.
/// Uses the `keyring` crate which wraps:
///   - Windows Credential Manager on Windows
///   - macOS Keychain on macOS
///   - libsecret / kwallet on Linux
use keyring::Entry;

const SERVICE: &str = "com.topscan.ScanToExternApp";
const ACCOUNT: &str = "ClaudeAPIKey";

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
