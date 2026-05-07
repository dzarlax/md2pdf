# md2pdf

Converts Markdown to PDF via [Typst](https://typst.app). Handles wide tables, Mermaid diagrams, code blocks with syntax highlighting, and Cyrillic text out of the box.

## Features

- Tables with styled header row
- Mermaid diagrams (rendered to SVG)
- ASCII diagrams via svgbob
- Fenced code blocks with language tag
- Bold, italic, inline code, lists
- Configurable language and font
- Finder Quick Action (right-click → Convert to PDF)
- Watch mode for live re-rendering

## Installation

One-liner (recommended — installs signed and notarized binaries):

```bash
curl -fsSL https://raw.githubusercontent.com/dzarlax/md2pdf/main/install-binary.sh | bash
```

This installs `md2pdf` and `typst` to `~/.local/bin`, and the **md2pdf Helper.app** Finder Service to `/Applications`.
After install, right-click any `.md` file in Finder → **Services → Convert to PDF**.

### From source

Requires Rust toolchain. Builds the helper locally — needs an Apple Developer ID for the Finder Service to register.

```bash
git clone https://github.com/dzarlax/md2pdf.git
cd md2pdf
make install
```

To uninstall:

```bash
make uninstall
```

## Usage

```bash
# Basic
md2pdf document.md

# Custom output path
md2pdf document.md --output ~/Desktop/report.pdf

# Russian document with specific font
md2pdf document.md --lang ru --font "PT Sans"

# Watch mode (re-renders on save)
md2pdf document.md --watch

# Custom typst binary
md2pdf document.md --typst-bin /usr/local/bin/typst
```

From Finder: right-click any `.md` file → **Quick Actions → Convert to PDF**. The PDF appears next to the source file.

## Options

| Option | Default | Description |
|---|---|---|
| `--output`, `-o` | `<input>.pdf` | Output PDF path |
| `--lang` | `en` | Document language for hyphenation |
| `--font` | `PT Sans` | Body font family |
| `--typst-bin` | auto | Path to typst binary |
| `--watch`, `-w` | off | Re-render on file change |

## Source file validation

Before converting, md2pdf automatically checks the source file for common Markdown issues:

- **Unclosed code fence** — a ` ``` ` block that is never closed
- **Markdown structure inside a code block** — headings or table rows inside an untagged code block (almost always a missing closing fence)
- **Heading count mismatch** — more `#` headings in the source than in the parsed document (some were swallowed by a code block)

Warnings are printed to stderr and conversion continues. The PDF may look broken in the flagged sections.

## How it works

1. Parses Markdown with [comrak](https://github.com/kivikakk/comrak) (CommonMark + tables, strikethrough, task lists)
2. Walks the AST and generates Typst markup
3. Renders to PDF with the bundled `typst` binary

Mermaid and svgbob diagrams are rendered to SVG files in `assets/diagrams/` next to the input file, then embedded in the PDF.

## Project structure

```
src/
  main.rs      — CLI, conversion orchestration, watch mode
  markdown.rs  — Markdown AST → Typst source
  diagrams.rs  — Mermaid and svgbob rendering
assets/
  Inter-Regular.ttf  — bundled fallback font
typst-bin            — bundled Typst 0.13 binary (macOS arm64)
install.sh           — installer script
Install md2pdf.command — double-click installer for macOS
```
