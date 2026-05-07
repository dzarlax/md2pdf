#!/bin/bash
set -e

INSTALL_DIR="$HOME/.local/bin"
SERVICES_DIR="$HOME/Library/Services"
HELPER_DIR="$(cd "$(dirname "$0")" && pwd)/md2pdf-helper"

echo "==> md2pdf installer"

# ── 1. Rust / Cargo ──────────────────────────────────────────────────────────
if ! command -v cargo &>/dev/null; then
    echo "==> Rust not found. Installing via rustup..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --quiet
    source "$HOME/.cargo/env"
fi

# ── 2. Build md2pdf ───────────────────────────────────────────────────────────
echo "==> Building md2pdf..."
cargo build --release --quiet

# ── 3. Install binaries ───────────────────────────────────────────────────────
mkdir -p "$INSTALL_DIR"

cp target/release/md2pdf "$INSTALL_DIR/md2pdf"
chmod +x "$INSTALL_DIR/md2pdf"
echo "    md2pdf  → $INSTALL_DIR/md2pdf"

if [[ -f "./typst-bin" ]]; then
    cp ./typst-bin "$INSTALL_DIR/typst"
    chmod +x "$INSTALL_DIR/typst"
    echo "    typst   → $INSTALL_DIR/typst"
elif ! command -v typst &>/dev/null; then
    echo "    typst not found in repo or PATH."
    echo "    Install with: brew install typst"
fi

# ── 4. PATH hint ──────────────────────────────────────────────────────────────
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
    else
        echo "    Add $INSTALL_DIR to your PATH manually."
    fi
fi

# ── 5. Cleanup any old broken Automator workflow ──────────────────────────────
if [[ -d "$SERVICES_DIR/Convert to PDF.workflow" ]]; then
    rm -rf "$SERVICES_DIR/Convert to PDF.workflow"
    echo "    Removed legacy Automator workflow."
fi

# ── 6. Finder Service (Swift helper) ──────────────────────────────────────────
echo "==> Installing Finder Service (md2pdf Helper)..."

if [[ -d "$HELPER_DIR" ]]; then
    DEVELOPER_ID="$(security find-identity -v -p codesigning 2>/dev/null \
        | grep "Developer ID Application" | head -1 \
        | sed -E 's/.*"(Developer ID Application: [^"]+)"/\1/')"

    if [[ -n "$DEVELOPER_ID" ]]; then
        echo "    Using signing identity: $DEVELOPER_ID"
        ( cd "$HELPER_DIR" && bash build.sh "$DEVELOPER_ID" )
    else
        echo "    No Developer ID found — using ad-hoc signing."
        echo "    NOTE: Ad-hoc signed services may not register reliably on macOS Sequoia+."
        ( cd "$HELPER_DIR" && bash build.sh )
    fi
else
    echo "    Skipping helper (md2pdf-helper directory not found)"
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo "Done! Usage:"
echo "  Terminal:  md2pdf document.md"
echo "  Finder:    right-click .md file → Services → Convert to PDF"
echo ""
echo "If 'Convert to PDF' is missing in the Services menu, enable it under:"
echo "  System Settings → Keyboard → Keyboard Shortcuts → Services → Files and Folders"
