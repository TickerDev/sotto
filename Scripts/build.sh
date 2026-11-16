#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

# Keep local TCC identity stable when one unambiguous development identity exists.
# Never persist a developer's personal certificate or team in the repository.
sotto_identity="${SOTTO_SIGNING_IDENTITY:-}"
sotto_team="${SOTTO_DEVELOPMENT_TEAM:-}"
if [ -z "$sotto_identity" ]; then
    sotto_identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"
    sotto_count="$(printf '%s\n' "$sotto_identities" | awk '/"Apple Development:/ { n++ } END { print n+0 }')"
    if [ "$sotto_count" = 1 ]; then
        sotto_identity="$(printf '%s\n' "$sotto_identities" | awk '/"Apple Development:/ { print $2 }')"
        if [ -z "$sotto_team" ]; then
            sotto_certificate="$(printf '%s\n' "$sotto_identities" | sed -nE 's/.*"(Apple Development:.*)".*/\1/p')"
            sotto_team="$(security find-certificate -c "$sotto_certificate" -p 2>/dev/null | openssl x509 -noout -subject -nameopt sep_multiline,sname 2>/dev/null | sed -nE 's/^[[:space:]]*OU[[:space:]]*=[[:space:]]*([A-Z0-9]{10})[[:space:]]*$/\1/p')"
        fi
        if [ -z "$sotto_team" ]; then sotto_identity="-"; fi
    else
        sotto_identity="-"
    fi
fi

if [ "$sotto_identity" = "-" ]; then
    xcodebuild -project Sotto.xcodeproj -scheme Sotto -configuration Debug -derivedDataPath build CODE_SIGN_IDENTITY=- build
else
    xcodebuild -project Sotto.xcodeproj -scheme Sotto -configuration Debug -derivedDataPath build \
        CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$sotto_identity" DEVELOPMENT_TEAM="$sotto_team" build
fi
