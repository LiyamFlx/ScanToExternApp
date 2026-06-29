#!/bin/bash
# Creates a stable self-signed code-signing certificate so the app keeps its
# Accessibility (and other TCC) permissions across rebuilds.
# Run ONCE. You'll be asked for your login/keychain password.
set -e

CERT_NAME="ScanToExternApp Self-Signed"

if security find-certificate -c "$CERT_NAME" >/dev/null 2>&1; then
  echo "Certificate '$CERT_NAME' already exists. Nothing to do."
  exit 0
fi

TMP=$(mktemp -d)
cat > "$TMP/cert.conf" <<EOF
[ req ]
distinguished_name = dn
x509_extensions = ext
prompt = no
[ dn ]
CN = $CERT_NAME
[ ext ]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:false
EOF

echo "Generating key + self-signed cert..."
openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
  -days 3650 -config "$TMP/cert.conf"

# Bundle into a PKCS#12 with no password
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -out "$TMP/cert.p12" -passout pass:

echo "Importing into login keychain (you'll be prompted for your password)..."
security import "$TMP/cert.p12" -k ~/Library/Keychains/login.keychain-db \
  -P "" -T /usr/bin/codesign

# Trust it for code signing
echo "Marking certificate as trusted for code signing..."
sudo security add-trusted-cert -d -r trustAsRoot \
  -p codeSign -k /Library/Keychains/System.keychain "$TMP/cert.pem" 2>/dev/null || \
  echo "(trust step skipped — codesign will still work with the login-keychain identity)"

rm -rf "$TMP"
echo ""
echo "Done. Verify with:  security find-identity -v -p codesigning"
