#!/bin/bash
set -e

# Build a release tarball ready for manual upload to GitHub Releases.
#
# Auto-detects Developer ID from keychain.
# For notarization, set env vars: APPLE_ID, APPLE_PASSWORD, APPLE_TEAM_ID
# (skipped if not provided — tarball still ships, but helper may show a warning
# when first opened on another Mac).

# Load credentials from .env if present
if [[ -f ".env" ]]; then
    set -a
    source .env
    set +a
fi

VERSION="$(grep '^version' Cargo.toml | head -1 | sed -E 's/.*"([^"]+)".*/\1/')"
TAG="v$VERSION"
DIST="dist"
TARBALL="md2pdf-${TAG}-darwin-universal.tar.gz"

echo "==> md2pdf release builder ($TAG)"

DEVELOPER_ID="$(security find-identity -v -p codesigning 2>/dev/null \
    | grep "Developer ID Application" | head -1 \
    | sed -E 's/.*"(Developer ID Application: [^"]+)"/\1/')"
if [[ -z "$DEVELOPER_ID" ]]; then
    echo "Error: no 'Developer ID Application' certificate in keychain."
    exit 1
fi
echo "    Signing identity: $DEVELOPER_ID"

# ── Clean ─────────────────────────────────────────────────────────────────────
rm -rf "$DIST"
mkdir -p "$DIST"

# ── Build Universal md2pdf binary ─────────────────────────────────────────────
echo "==> Building Universal md2pdf binary..."
rustup target add aarch64-apple-darwin x86_64-apple-darwin >/dev/null 2>&1

cargo build --release --target aarch64-apple-darwin --quiet
cargo build --release --target x86_64-apple-darwin --quiet

lipo -create \
    target/aarch64-apple-darwin/release/md2pdf \
    target/x86_64-apple-darwin/release/md2pdf \
    -output "$DIST/md2pdf"

# ── Bundle typst (download if not present locally) ───────────────────────────
if [[ ! -f typst-bin ]]; then
    echo "==> Fetching typst Universal binary..."
    TYPST_VER="$(curl -fsSL https://api.github.com/repos/typst/typst/releases/latest \
        | grep '"tag_name"' | head -1 | sed -E 's/.*"v?([^"]+)".*/\1/')"
    TMP_TYPST="$(mktemp -d)"
    # Download both arches and lipo together for Universal
    for ARCH in aarch64 x86_64; do
        curl -fsSL "https://github.com/typst/typst/releases/download/v${TYPST_VER}/typst-${ARCH}-apple-darwin.tar.xz" \
            | tar -xJ -C "$TMP_TYPST"
        mv "$TMP_TYPST/typst-${ARCH}-apple-darwin/typst" "$TMP_TYPST/typst-${ARCH}"
    done
    lipo -create "$TMP_TYPST/typst-aarch64" "$TMP_TYPST/typst-x86_64" -output typst-bin
    chmod +x typst-bin
    rm -rf "$TMP_TYPST"
fi
cp typst-bin "$DIST/typst"
chmod +x "$DIST/typst"

# ── Sign binaries ─────────────────────────────────────────────────────────────
echo "==> Signing binaries..."
codesign --force --options runtime --timestamp \
    --sign "$DEVELOPER_ID" "$DIST/md2pdf"
codesign --force --options runtime --timestamp \
    --sign "$DEVELOPER_ID" "$DIST/typst"

# ── Build helper app ──────────────────────────────────────────────────────────
echo "==> Building helper app..."
( cd md2pdf-helper && bash build.sh "$DEVELOPER_ID" )
cp -R "/Applications/md2pdf Helper.app" "$DIST/md2pdf Helper.app"

# ── Notarize (optional) ───────────────────────────────────────────────────────
if [[ -n "$APPLE_ID" && -n "$APPLE_PASSWORD" && -n "$APPLE_TEAM_ID" ]]; then
    echo "==> Notarizing helper app..."
    ditto -c -k --keepParent "$DIST/md2pdf Helper.app" "$DIST/helper.zip"
    xcrun notarytool submit "$DIST/helper.zip" \
        --apple-id "$APPLE_ID" \
        --password "$APPLE_PASSWORD" \
        --team-id "$APPLE_TEAM_ID" \
        --wait
    xcrun stapler staple "$DIST/md2pdf Helper.app"
    rm "$DIST/helper.zip"

    echo "==> Notarizing md2pdf binary..."
    # Binaries are notarized by zipping them
    ditto -c -k "$DIST/md2pdf" "$DIST/md2pdf.zip"
    xcrun notarytool submit "$DIST/md2pdf.zip" \
        --apple-id "$APPLE_ID" \
        --password "$APPLE_PASSWORD" \
        --team-id "$APPLE_TEAM_ID" \
        --wait
    rm "$DIST/md2pdf.zip"
else
    echo "==> Skipping notarization (set APPLE_ID, APPLE_PASSWORD, APPLE_TEAM_ID to enable)"
fi

# ── Package ───────────────────────────────────────────────────────────────────
echo "==> Packaging tarball..."
( cd "$DIST" && tar -czf "$TARBALL" md2pdf typst "md2pdf Helper.app" )

echo ""
echo "✓ Release ready: $DIST/$TARBALL"
echo ""
echo "Next steps:"
echo "  1. git tag $TAG && git push --tags"
echo "  2. Create release at: https://github.com/dzarlax/md2pdf/releases/new"
echo "     - Tag: $TAG"
echo "     - Upload: $DIST/$TARBALL"
echo ""
echo "Or via gh CLI:"
echo "  gh release create $TAG $DIST/$TARBALL --generate-notes"
