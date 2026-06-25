/// Windows Credential Manager storage for the Claude API key.
/// Equivalent of Mac Keychain (SecItemAdd / SecItemCopyMatching).
/// Uses the windows-credentials crate which wraps CredWrite/CredRead.
const TARGET: &str = "ScanToExternApp/ClaudeAPIKey";

#[cfg(windows)]
pub fn save_api_key(key: &str) -> anyhow::Result<()> {
    use windows_credentials::Credential;
    Credential::new(TARGET, "claudeAPIKey", key.as_bytes()).save()?;
    Ok(())
}

#[cfg(windows)]
pub fn load_api_key() -> anyhow::Result<String> {
    use windows_credentials::Credential;
    let cred = Credential::load(TARGET)?;
    Ok(String::from_utf8(cred.credential_blob)?)
}

#[cfg(windows)]
pub fn delete_api_key() -> anyhow::Result<()> {
    use windows_credentials::Credential;
    Credential::delete(TARGET)?;
    Ok(())
}

// Stubs for non-Windows builds
#[cfg(not(windows))]
pub fn save_api_key(_key: &str) -> anyhow::Result<()> { Ok(()) }
#[cfg(not(windows))]
pub fn load_api_key() -> anyhow::Result<String> { Ok(String::new()) }
#[cfg(not(windows))]
pub fn delete_api_key() -> anyhow::Result<()> { Ok(()) }
