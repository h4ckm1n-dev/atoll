#!/bin/zsh

# Build a signed (and optionally notarized) Atoll DMG locally, then
# upload it to a GitHub Release.
#
# Usage:
#   zsh scripts/release-to-github.sh                 # uses current git tag
#   zsh scripts/release-to-github.sh v1.1.0-atoll    # explicit tag
#   zsh scripts/release-to-github.sh --no-upload     # build only, skip GH push
#
# Prerequisites:
#   - "Developer ID Application: <Name> (<Team>)" cert in login keychain
#     (run `security find-identity -p codesigning -v` to confirm)
#   - `gh` CLI authenticated to a GitHub account with write access to
#     the target repo (run `gh auth status`)
#   - For notarization (optional): a notarytool keychain profile named
#     `atoll-notary`. Set up once with:
#         xcrun notarytool store-credentials atoll-notary \
#           --apple-id <your-apple-id-email> \
#           --team-id 8X4342NAZV \
#           --password <app-specific-password>
#     The script auto-detects this profile and notarizes + staples the
#     result. Without it, the DMG is signed but not notarized — users
#     will need to right-click → Open on first launch.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

# ─── Args ─────────────────────────────────────────────────────────────
upload=true
tag=""
for arg in "$@"; do
    case "$arg" in
        --no-upload) upload=false ;;
        v*)          tag="$arg" ;;
        *)
            echo "usage: zsh scripts/release-to-github.sh [<tag>] [--no-upload]" >&2
            exit 64
            ;;
    esac
done

if [[ -z "$tag" ]]; then
    tag="$(git describe --tags --abbrev=0 2>/dev/null || true)"
fi
if [[ -z "$tag" ]]; then
    echo "ERROR: no tag found. Either pass one (zsh scripts/release-to-github.sh v1.2.0-atoll) or run from a tagged checkout." >&2
    exit 1
fi
echo "Using tag: $tag"

# Strip the "v" + "-atoll" suffix for CFBundleShortVersionString — the
# Info.plist version field expects 1.1.0, not v1.1.0-atoll.
version="${tag#v}"
version="${version%-atoll}"
echo "App version: $version"

# ─── Detect signing identity ──────────────────────────────────────────
echo ""
echo "==> Detecting Developer ID Application certificate..."
identity="$(security find-identity -p codesigning -v "$HOME/Library/Keychains/login.keychain-db" 2>/dev/null \
    | sed -nE 's/.*"(Developer ID Application: [^"]+)".*/\1/p' \
    | head -n 1)"

if [[ -z "$identity" ]]; then
    echo "ERROR: no Developer ID Application identity found in login keychain." >&2
    echo "Run 'security find-identity -p codesigning -v' to inspect." >&2
    echo "Without one, fall back to the CI's ad-hoc-signed artifact:" >&2
    echo "  https://github.com/h4ckm1n-dev/atoll/actions" >&2
    exit 1
fi
echo "Found: $identity"

# ─── Detect notarization profile (optional) ───────────────────────────
notary_profile=""
if xcrun notarytool history --keychain-profile atoll-notary >/dev/null 2>&1; then
    notary_profile="atoll-notary"
    echo "Found notarytool keychain profile: $notary_profile"
else
    echo "No 'atoll-notary' notarytool profile — DMG will be signed but"
    echo "NOT notarized. Users will need right-click → Open on first launch."
    echo "To enable notarization, set up the profile once:"
    echo ""
    echo "    xcrun notarytool store-credentials atoll-notary \\"
    echo "      --apple-id <your-apple-id-email> \\"
    echo "      --team-id 8X4342NAZV \\"
    echo "      --password <app-specific-password>"
    echo ""
fi

# ─── Build + sign ─────────────────────────────────────────────────────
echo ""
echo "==> Building + signing universal release..."
ATOLL_VERSION="$version" \
ATOLL_BUILD_NUMBER="$(git rev-list --count HEAD)" \
ATOLL_UNIVERSAL="true" \
ATOLL_SIGN_IDENTITY="$identity" \
zsh scripts/package-app.sh

dmg_path="output/package/Atoll.dmg"
zip_path="output/package/Atoll.zip"
bundle_path="output/package/Atoll.app"

[[ -f "$dmg_path" ]] || { echo "ERROR: DMG not produced at $dmg_path" >&2; exit 1; }
echo "Built: $dmg_path ($(du -h "$dmg_path" | awk '{print $1}'))"
echo "       $zip_path ($(du -h "$zip_path" | awk '{print $1}'))"

# ─── Notarize + staple (if profile available) ─────────────────────────
notarized="false"
if [[ -n "$notary_profile" ]]; then
    echo ""
    echo "==> Notarizing (this can take 1-10 min)..."
    if xcrun notarytool submit "$zip_path" \
        --keychain-profile "$notary_profile" \
        --wait --timeout 15m
    then
        echo "Stapling notarization to .app..."
        xcrun stapler staple -v "$bundle_path"

        # Re-create zip with the now-stapled bundle so the zip ships a
        # ticket users can verify offline.
        rm -f "$zip_path"
        ditto -c -k --keepParent "$bundle_path" "$zip_path"

        # Re-sign the DMG (the .app inside is now stapled but the DMG
        # itself needs its own notarization round).
        codesign --force --sign "$identity" --timestamp "$dmg_path"
        echo "Notarizing DMG..."
        if xcrun notarytool submit "$dmg_path" \
            --keychain-profile "$notary_profile" \
            --wait --timeout 15m
        then
            xcrun stapler staple -v "$dmg_path"
            notarized="true"
            echo "✅ Notarized + stapled."
        else
            echo "⚠ DMG notarization failed — .app is notarized but DMG is not." >&2
        fi
    else
        echo "⚠ Notarization failed — .app is signed but not notarized." >&2
        echo "  Users will need right-click → Open on first launch." >&2
    fi
fi

# ─── Verify signature ─────────────────────────────────────────────────
echo ""
echo "==> Final signature check..."
codesign -dv --verbose=2 "$bundle_path" 2>&1 | grep -E "Authority|Identifier|TeamIdentifier" | head -5
spctl -a -vv -t install "$dmg_path" 2>&1 | head -3 || true

# ─── Upload to GitHub Release ────────────────────────────────────────
if [[ "$upload" != "true" ]]; then
    echo ""
    echo "==> Skipping upload (--no-upload). Artifacts at output/package/"
    exit 0
fi

if ! gh auth status >/dev/null 2>&1; then
    echo "ERROR: gh CLI not authenticated. Run 'gh auth login' first." >&2
    exit 1
fi

repo="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)"
if [[ -z "$repo" ]]; then
    echo "ERROR: not in a GitHub-tracked repo (gh repo view failed)." >&2
    exit 1
fi

echo ""
echo "==> Uploading to $repo release $tag..."

dmg_label="Atoll.dmg (macOS, Universal, signed"
zip_label="Atoll.zip (macOS, Universal, signed"
if [[ "$notarized" == "true" ]]; then
    dmg_label="$dmg_label + notarized)"
    zip_label="$zip_label + notarized)"
else
    dmg_label="$dmg_label, ad-hoc Gatekeeper)"
    zip_label="$zip_label, ad-hoc Gatekeeper)"
fi

if gh release view "$tag" --repo "$repo" >/dev/null 2>&1; then
    echo "Release exists — uploading assets with --clobber"
    gh release upload "$tag" \
        "$dmg_path#$dmg_label" \
        "$zip_path#$zip_label" \
        --clobber \
        --repo "$repo"
else
    echo "Release does not exist — creating draft"
    gh release create "$tag" \
        --title "Atoll $tag" \
        --generate-notes \
        --draft \
        --repo "$repo" \
        "$dmg_path#$dmg_label" \
        "$zip_path#$zip_label"
fi

release_url="$(gh release view "$tag" --repo "$repo" --json url -q .url 2>/dev/null || echo "")"
echo ""
echo "✅ Done."
[[ -n "$release_url" ]] && echo "   $release_url"
