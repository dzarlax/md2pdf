# md2pdf

Markdown → PDF converter. Parses MD with comrak, generates Typst source, renders with bundled `typst-bin`. Ships a signed/notarized macOS Helper.app that registers a Finder Service ("Convert to PDF") via NSServices.

## Commands

```bash
cargo build                          # debug build
cargo build --release                # release build
cargo run -- test.md --lang ru       # run directly
make install                         # build from source + install + build helper
make uninstall                       # remove all installed files
make release                         # build, sign, notarize, package release tarball
```

End-user install (signed/notarized binaries from latest GitHub release):

```bash
curl -fsSL https://raw.githubusercontent.com/dzarlax/md2pdf/main/install-binary.sh | bash
```

## Architecture

```
src/main.rs       CLI (clap), orchestrates run_conversion(), watch_mode()
src/markdown.rs   convert_to_typst() — comrak AST walker → Typst source string
src/diagrams.rs   render_mermaid(), render_svgbob() — thin wrappers
md2pdf-helper/    Swift app bundle: registers NSService for Finder right-click
release.sh        Local release builder: lipo Universal + sign + notarize + tarball
install.sh        Source build install (developers)
install-binary.sh Curl-friendly download from GitHub Releases (end users)
```

### Conversion pipeline

1. `fs::canonicalize(input)` → `root_dir` (parent of input file).
2. Per-process temp dir at `/tmp/md2pdf-<pid>-<ns>/`. All intermediates live here:
   - Typst source: `<tmp>/main.typ`
   - Diagram SVGs: `<tmp>/diagrams/<uuid>.svg` (created lazily, only if document has Mermaid/svgbob)
3. `typst compile <tmp>/main.typ output.pdf --root /`
4. Temp dir removed after the typst process exits, regardless of success/failure.

**Why `--root /`**: the .typ source is in `/tmp/...` while user images are under `/Users/.../md_dir/`. Typst forbids cross-root references, so we use the filesystem root and emit absolute paths in the generated Typst source for both diagrams and user images.

The user's directory ends up containing only the resulting `.pdf` — no stray `.tmp_typst/` or `assets/` left behind.

### Typst binary resolution

`--typst-bin` flag → `./typst-bin` if exists → `typst` in PATH.

`typst-bin` is gitignored. `release.sh` downloads a Universal typst binary from the typst project's GitHub releases if `./typst-bin` is missing locally.

### Watch mode

Polls `fs::metadata().modified()` every 500ms. `run_conversion` is wrapped in `tokio::task::spawn_blocking` to avoid blocking the async runtime.

## Key implementation gotchas

**`/*` comment bug**: Typst treats `/*` as block comment start. MD bold like `**Total src/**` naively produces `*Total src/*` in Typst, where `/` + `*` = `/*` starts a comment. Fix: use `#strong[...]` / `#emph[...]` function syntax instead of `*...*` / `_..._` markup.

**`escape_typst`**: only called on `NodeValue::Text` nodes (plain text). Escapes `\`, `#`, `$`, `@`, `*`, `_`, `` ` ``, `<`, `~`. Not called inside raw blocks or function arguments.

**Code block fencing**: `count_max_backticks(content) + 1` backticks for the fence, to handle code that contains backtick sequences. Minimum 3 backticks.

**Inline code wrapping in tables**: Typst inline raw doesn't wrap on non-space chars. The `Code` handler inserts U+200B (zero-width space) after `_`, `-`, `.`, `/`, `\` so long filenames/paths break inside narrow cells without changing visible output.

**`SoftBreak`**: single newline in MD source within a paragraph → space in output (CommonMark spec). `LineBreak` (two trailing spaces) → `\\\n` (hard line break in Typst).

**List items**: `NodeValue::Item` children include `NodeValue::Paragraph` which would add `\n\n`. Instead, Item handler recurses into paragraph's children directly and emits a single `\n`.

**Table header**: `NodeValue::TableRow(is_header: bool)`. When true, wrap in `table.header(...)` for Typst semantic headers and proper page-repeat behavior.

**Image paths**: emitted as absolute filesystem paths (`root_dir.join(src)`) so they resolve regardless of where the .typ source lives. Remote `http(s)://` URLs are passed through unchanged.

## Finder Service (md2pdf Helper.app)

Lives at `md2pdf-helper/`. A minimal AppKit background app (`LSBackgroundOnly = true`) that calls `NSApp.servicesProvider = ServiceHandler()` and exposes `convertToPDF:userData:error:` via `NSServices` in `Info.plist`. Installed to `/Applications/md2pdf Helper.app` and registered via `pbs -update`.

`NSRequiredContext.NSApplicationIdentifier = com.apple.finder` scopes the menu item to Finder context. `NSSendFileTypes = [net.daringfireball.markdown, public.plain-text]` activates only on those file types.

Built and signed by `md2pdf-helper/build.sh`. **Do not use `codesign --deep`** (deprecated, fails notarization) — sign the inner binary first, then the bundle. **Always `rm -rf` the destination `.app` before `cp -R`** — copying onto an existing bundle creates a nested `.app/.app` that produces "unsealed contents" errors.

Why NSService and not Quick Action: macOS Sequoia rejects user-created Automator workflows in `~/Library/Services/` (lsregister returns "-10811 from spotlight"; the `com.apple.provenance` xattr on user-installed bundles can't be removed and blocks Spotlight scan). `com.apple.ui-services` App Extensions appear in the Share Sheet, not in Finder right-click. NSServices in a signed/notarized app register reliably via pbs.

## Release

`make release` runs `release.sh`:

1. Loads `.env` for `APPLE_ID`, `APPLE_PASSWORD` (app-specific), `APPLE_TEAM_ID`.
2. Auto-detects Developer ID from keychain via `security find-identity`.
3. Builds Universal `md2pdf` (lipo arm64 + x86_64), signs `md2pdf` and `typst`.
4. Builds and signs helper.app via `md2pdf-helper/build.sh`.
5. Notarizes both via `xcrun notarytool ... --wait`, staples ticket to helper.
6. Packages `dist/md2pdf-vX.Y.Z-darwin-universal.tar.gz`.
7. Prints `gh release create` command for manual upload.

Local skill `release-md2pdf` (in `.claude/skills/`) automates the bump → build → tag → push → release loop. Skill directory is gitignored.

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
