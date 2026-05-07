# md2pdf

Markdown → PDF converter. Parses MD with comrak, generates Typst source, renders with bundled `typst-bin`.

## Commands

```bash
cargo build                          # debug build
cargo build --release                # release build
cargo run -- test.md --lang ru       # run directly
cargo install --path .               # install globally to ~/.cargo/bin
bash install.sh                      # full install (binaries + Quick Action)
make install                         # same as install.sh
make uninstall                       # remove all installed files
```

## Architecture

```
main.rs      CLI (clap), orchestrates run_conversion(), watch_mode()
markdown.rs  convert_to_typst() — comrak AST walker → Typst source string
diagrams.rs  render_mermaid(), render_svgbob() — thin wrappers
```

### Conversion pipeline

1. `fs::canonicalize(input)` → `root_dir` (parent of input file)
2. Diagrams saved to `root_dir/assets/diagrams/<uuid>.svg`
3. Typst source written to `root_dir/.tmp_typst/main.typ`
4. `typst compile main.typ output.pdf --root root_dir --font-path root_dir/assets`

All paths are relative to `root_dir`, not CWD. This is intentional — allows running `md2pdf` from any directory.

### Typst binary resolution

`--typst-bin` flag → `./typst-bin` if exists → `typst` in PATH.

### Watch mode

Polls `fs::metadata().modified()` every 500ms. `run_conversion` is wrapped in `tokio::task::spawn_blocking` to avoid blocking the async runtime.

## Key implementation gotchas

**`/*` comment bug**: Typst treats `/*` as block comment start. MD bold like `**Total src/**` naively produces `*Total src/*` in Typst, where `/` + `*` = `/*` starts a comment. Fix: use `#strong[...]` / `#emph[...]` function syntax instead of `*...*` / `_..._` markup.

**`escape_typst`**: only called on `NodeValue::Text` nodes (plain text). Escapes `\`, `#`, `$`, `@`, `*`, `_`, `` ` ``, `<`, `~`. Not called inside raw blocks or function arguments.

**Code block fencing**: `count_max_backticks(content) + 1` backticks for the fence, to handle code that contains backtick sequences. Minimum 3 backticks.

**`SoftBreak`**: single newline in MD source within a paragraph → space in output (CommonMark spec). `LineBreak` (two trailing spaces) → `\\\n` (hard line break in Typst).

**List items**: `NodeValue::Item` children include `NodeValue::Paragraph` which would add `\n\n`. Instead, Item handler recurses into paragraph's children directly and emits a single `\n`.

**Table header**: `NodeValue::TableRow(is_header: bool)`. When true, wrap in `table.header(...)` for Typst semantic headers and proper page-repeat behavior.

## Dependencies

| Crate | Purpose |
|---|---|
| `comrak` | Markdown parser (CommonMark + extensions) |
| `clap` | CLI argument parsing |
| `anyhow` | Error handling |
| `tokio` | Async runtime for watch mode + spawn_blocking |
| `uuid` | Unique filenames for diagram SVGs |
| `mermaid-rs-renderer` | Mermaid → SVG |
| `svgbob` | ASCII art → SVG |

## Finder Quick Action

Installed at `~/Library/Services/Convert to PDF.workflow`. Shell script inside sets `PATH` explicitly (Automator does not source `.zshrc`) then calls `md2pdf "$f"` for each selected `.md` file. On success, shows a macOS notification via `osascript`.
