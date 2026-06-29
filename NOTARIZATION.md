# Notarization — shipping a no-warnings macOS DMG

The current `ScanToExternApp-5.0.0.dmg` is signed with a **self-signed** certificate.
On a fresh Mac, Gatekeeper will block the first launch and the user has to
right-click → Open. To make the app open with **zero warnings** on every Mac, it
needs to be signed with an **Apple Developer ID** and **notarized** by Apple.

This file lists exactly what's needed and the steps I'll run when you give me the
credentials.

---

## What you need to provide

To notarize, three things are required — and there is no way around any of them:

1. **Apple Developer Program membership** — $99/year, https://developer.apple.com/programs/
   - Individual or Organization is fine.
2. **A Developer ID Application certificate**, installed in the login keychain.
   - Created from https://developer.apple.com/account/resources/certificates → `+` → **Developer ID Application**.
   - Download the `.cer`, double-click to install. Verify with `security find-identity -v -p codesigning` — you should see a line like `"Developer ID Application: Your Name (TEAMID)"`.
3. **An app-specific password for `notarytool`** (NOT your Apple ID password).
   - Create at https://appleid.apple.com → Sign-In and Security → App-Specific Passwords.
   - Label it e.g. `notarytool-scanapp`. Save the 19-char string — you only see it once.

You also need your **Team ID** (10 chars, e.g. `RBRX2Y72NR`). Find it at
https://developer.apple.com/account → Membership.

## What you give me, in one message

```
APPLE_ID=you@example.com
TEAM_ID=ABCDE12345
APP_PWD=xxxx-xxxx-xxxx-xxxx     # the app-specific password
SIGNING_IDENTITY="Developer ID Application: Your Name (ABCDE12345)"
```

Once I have those, I store the credentials in the keychain (no plaintext on disk):

```bash
xcrun notarytool store-credentials "AC_SCANAPP" \
  --apple-id "$APPLE_ID" \
  --team-id "$TEAM_ID" \
  --password "$APP_PWD"
```

Then I sign + notarize + staple. Single sequence end-to-end:

```bash
cd /Users/liyam/NewApp/mac
/opt/homebrew/bin/xcodegen generate
xcodebuild -project ScanToExternApp.xcodeproj -scheme ScanToExternApp \
  -configuration Release -derivedDataPath build clean build

APP=build/Build/Products/Release/ScanToExternApp.app

# Sign with the Developer ID (hardened runtime + disable-library-validation
# entitlement — same recipe as the self-signed build, just a real cert)
codesign --force --options runtime --timestamp \
  --sign "$SIGNING_IDENTITY" \
  --entitlements /tmp/scanapp.entitlements \
  "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

# Build the DMG with the same layout as today
STAGE=/tmp/scanapp-dmg-stage
rm -rf "$STAGE" && mkdir "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
DMG=build/ScanToExternApp-5.0.0.dmg
hdiutil create -volname "ScanToExternApp" -srcfolder "$STAGE" \
  -ov -format UDZO "$DMG"
codesign --force --sign "$SIGNING_IDENTITY" --timestamp "$DMG"

# Submit for notarization — typically 1–5 minutes, this blocks until Apple replies
xcrun notarytool submit "$DMG" --keychain-profile "AC_SCANAPP" --wait

# Staple the ticket onto the DMG (so notarization works offline too)
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl -a -t open --context context:primary-signature -v "$DMG"
```

After `stapler validate` reports `The validate action worked!` the DMG is good
to ship.

## What the user sees with a notarized + stapled DMG

- Double-clicking the DMG — opens, no warning.
- Dragging the .app to Applications — copies cleanly.
- First double-click of the .app — opens silently, no Gatekeeper dialog, no
  "downloaded from the internet" warning (Gatekeeper checks the stapled
  notarization ticket and lets it through).
- They never see "unidentified developer" or have to right-click.

You don't need to tell users anything about quarantine. macOS already strips it
on first launch for notarized apps.

## If a user did download an un-notarized build (this DMG today)

For the self-signed DMG that exists right now, downloaded copies will be
quarantined. The user has two options:

```bash
# Easiest: tell users to right-click → Open in Finder ONCE.
# Alternative for power users / scripted setup:
xattr -dr com.apple.quarantine /Applications/ScanToExternApp.app
```

`xattr -dr com.apple.quarantine` removes the quarantine xattr recursively. The
app launches normally after that. This step is **not needed** once the DMG is
notarized.

## Renewing

- The Developer ID Application cert is valid for 5 years.
- The notarization ticket on a DMG never expires.
- App-specific passwords stay valid until revoked.
- Your Developer Program membership has to be renewed yearly ($99). If it lapses,
  your existing notarized builds keep working; you just can't notarize new ones
  until you renew.
