#!/bin/bash
set -e

REPO="dzarlax/md2pdf"
INSTALL_DIR="$HOME/.local/bin"
APP_DIR="/Applications"

echo "==> md2pdf installer"

if [[ "$(uname)" != "Darwin" ]]; then
    echo "Error: macOS only."
    exit 1
fi

# Get latest release tag
echo "==> Fetching latest release..."
TAG="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
    | grep '"tag_name"' | head -1 | sed -E 's/.*"([^"]+)".*/\1/')"
if [[ -z "$TAG" ]]; then
    echo "Error: failed to fetch latest release."
    exit 1
fi
echo "    Found: $TAG"

URL="https://github.com/$REPO/releases/download/$TAG/md2pdf-$TAG-darwin-universal.tar.gz"
TMP="$(mktemp -d)"
trap "rm -rf $TMP" EXIT

echo "==> Downloading..."
curl -fsSL "$URL" -o "$TMP/release.tar.gz"
tar -xzf "$TMP/release.tar.gz" -C "$TMP"

# ── Install binaries ──────────────────────────────────────────────────────────
mkdir -p "$INSTALL_DIR"

cp "$TMP/md2pdf" "$INSTALL_DIR/md2pdf"
chmod +x "$INSTALL_DIR/md2pdf"
xattr -dr com.apple.quarantine "$INSTALL_DIR/md2pdf" 2>/dev/null || true
echo "    md2pdf  → $INSTALL_DIR/md2pdf"

if [[ -f "$TMP/typst" ]]; then
    cp "$TMP/typst" "$INSTALL_DIR/typst"
    chmod +x "$INSTALL_DIR/typst"
    xattr -dr com.apple.quarantine "$INSTALL_DIR/typst" 2>/dev/null || true
    echo "    typst   → $INSTALL_DIR/typst"
fi

# ── PATH hint ─────────────────────────────────────────────────────────────────
if ! echo "$PATH" | grep -q "$INSTALL_DIR"; then
    SHELL_RC=""
    if [[ "$SHELL" == */zsh ]]; then SHELL_RC="$HOME/.zshrc"
    elif [[ "$SHELL" == */bash ]]; then SHELL_RC="$HOME/.bash_profile"
    fi
    if [[ -n "$SHELL_RC" ]]; then
        echo "" >> "$SHELL_RC"
        echo "export PATH=\"$INSTALL_DIR:\$PATH\"" >> "$SHELL_RC"
        echo "    Added $INSTALL_DIR to PATH in $SHELL_RC"
        echo "    Run: source $SHELL_RC"
    fi
fi

# ── Cleanup any old broken Automator workflow ────────────────────────────────
if [[ -d "$HOME/Library/Services/Convert to PDF.workflow" ]]; then
    rm -rf "$HOME/Library/Services/Convert to PDF.workflow"
fi

# ── Install helper app (Finder Service) ───────────────────────────────────────
if [[ -d "$TMP/md2pdf Helper.app" ]]; then
    echo "==> Installing Finder Service..."
    rm -rf "$APP_DIR/md2pdf Helper.app"
    cp -R "$TMP/md2pdf Helper.app" "$APP_DIR/md2pdf Helper.app"
    xattr -dr com.apple.quarantine "$APP_DIR/md2pdf Helper.app" 2>/dev/null || true
    open "$APP_DIR/md2pdf Helper.app"
    sleep 2
    /System/Library/CoreServices/pbs -update 2>/dev/null || true
    echo "    md2pdf Helper.app → $APP_DIR"
fi

echo ""
echo "Done!"
echo "  Terminal:  md2pdf document.md"
if [[ -d "$APP_DIR/md2pdf Helper.app" ]]; then
    echo "  Finder:    right-click .md file → Services → Convert to PDF"
    echo ""
    echo "  If 'Convert to PDF' is missing in Services, enable it in:"
    echo "  System Settings → Keyboard → Keyboard Shortcuts → Services → Files and Folders"
fi
