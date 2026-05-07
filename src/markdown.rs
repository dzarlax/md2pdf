use comrak::{parse_document, Arena, ComrakOptions};
use comrak::nodes::{AstNode, NodeValue};
use crate::diagrams;
use std::fs;
use std::path::Path;
use uuid::Uuid;

fn make_options() -> ComrakOptions<'static> {
    let mut options = ComrakOptions::default();
    options.extension.table = true;
    options.extension.strikethrough = true;
    options.extension.autolink = true;
    options.extension.tasklist = true;
    options
}

// ── Linter ────────────────────────────────────────────────────────────────────

pub fn lint(md: &str) -> Vec<String> {
    let mut warnings = Vec::new();

    warnings.extend(check_unclosed_fences(md));

    let arena = Arena::new();
    let root = parse_document(&arena, md, &make_options());

    warnings.extend(check_code_block_content(root));
    warnings.extend(check_heading_count(md, root));

    warnings
}

/// Check 1 — unclosed fences (raw text scan).
/// Detects a fence that is opened but never closed before EOF.
fn check_unclosed_fences(md: &str) -> Vec<String> {
    let mut fence_open: Option<(usize, char, usize)> = None; // (line, char, len)

    for (i, line) in md.lines().enumerate() {
        let trimmed = line.trim_start();
        let first = trimmed.chars().next();

        match (fence_open, first) {
            (None, Some(c @ '`')) | (None, Some(c @ '~')) => {
                let len = trimmed.chars().take_while(|&ch| ch == c).count();
                if len >= 3 {
                    fence_open = Some((i + 1, c, len));
                }
            }
            (Some((_, fc, min_len)), Some(fc_cur)) if fc_cur == fc => {
                let len = trimmed.chars().take_while(|&ch| ch == fc_cur).count();
                if len >= min_len && trimmed[len..].trim().is_empty() {
                    fence_open = None;
                }
            }
            _ => {}
        }
    }

    if let Some((line, _, _)) = fence_open {
        vec![format!("line {line}: code fence is never closed")]
    } else {
        vec![]
    }
}

/// Check 2 — suspicious Markdown inside code blocks (AST scan).
/// A heading or table row inside an untagged code block is almost certainly
/// a missing closing fence.
fn check_code_block_content<'a>(node: &'a AstNode<'a>) -> Vec<String> {
    let mut warnings = Vec::new();
    walk_code_blocks(node, &mut warnings);
    warnings
}

fn walk_code_blocks<'a>(node: &'a AstNode<'a>, warnings: &mut Vec<String>) {
    if let NodeValue::CodeBlock(c) = &node.data.borrow().value {
        // Only check untagged blocks — tagged ones (python, bash, …) legitimately
        // use # for comments and | in syntax.
        if c.info.trim().is_empty() {
            for line in c.literal.lines() {
                let t = line.trim_start();

                let looks_like_heading = t.starts_with('#')
                    && t.trim_start_matches('#').starts_with(' ');

                let looks_like_table = t.starts_with('|')
                    && t.trim_end().ends_with('|')
                    && t.len() > 2;

                if looks_like_heading || looks_like_table {
                    warnings.push(format!(
                        "code block contains a line that looks like Markdown structure: {:?} \
                         — possible missing closing fence",
                        line.trim()
                    ));
                    break; // one warning per block is enough
                }
            }
        }
    }
    for child in node.children() {
        walk_code_blocks(child, warnings);
    }
}

/// Check 3 — heading count mismatch between raw source and parsed AST.
/// If source has more `# Heading` lines than the AST has Heading nodes,
/// some headings were swallowed by a code block.
fn check_heading_count<'a>(md: &str, root: &'a AstNode<'a>) -> Vec<String> {
    let raw = md
        .lines()
        .filter(|l| {
            let t = l.trim_start();
            t.starts_with('#') && t.trim_start_matches('#').starts_with(' ')
        })
        .count();

    let parsed = count_headings(root);

    if raw > parsed {
        vec![format!(
            "{raw} headings in source, {parsed} parsed — {} likely swallowed by a code block",
            raw - parsed
        )]
    } else {
        vec![]
    }
}

fn count_headings<'a>(node: &'a AstNode<'a>) -> usize {
    let self_count = usize::from(matches!(
        &node.data.borrow().value,
        NodeValue::Heading(_)
    ));
    node.children().fold(self_count, |acc, child| acc + count_headings(child))
}

pub fn convert_to_typst(
    md: &str,
    lang: &str,
    font: &str,
    root_dir: &Path,
    diagrams_dir: &Path,
) -> String {
    let arena = Arena::new();
    let root = parse_document(&arena, md, &make_options());

    // diagrams_dir is created lazily on first SVG write.

    let mut typst = String::new();

    typst.push_str(&format!(
        "#set text(font: \"{}\", size: 11pt, lang: \"{}\")\n",
        font, lang
    ));
    typst.push_str(r#"#set page(
    margin: (x: 2.5cm, y: 3cm),
    header: [
        #set text(8pt)
        #smallcaps("Smart Markdown Generator")
        #h(1fr)
        #datetime.today().display()
    ],
    footer: [
        #set text(8pt)
        #h(1fr)
        #context counter(page).display()
    ]
)
#set par(justify: true, leading: 0.65em)
#let pointy_heading(it) = {
    pad(y: 0.5em, it)
}

#show heading: it => [
    #pointy_heading(it)
]

"#);

    walk_nodes(root, &mut typst, root_dir, diagrams_dir);

    typst
}

fn walk_nodes<'a>(node: &'a AstNode<'a>, out: &mut String, root_dir: &Path, diagrams_dir: &Path) {
    match &node.data.borrow().value {
        NodeValue::Document => {
            for child in node.children() {
                walk_nodes(child, out, root_dir, diagrams_dir);
            }
        }
        NodeValue::Heading(h) => {
            let prefix = "=".repeat(h.level as usize);
            out.push_str(&format!("{} ", prefix));
            for child in node.children() {
                walk_nodes(child, out, root_dir, diagrams_dir);
            }
            out.push_str("\n\n");
        }
        NodeValue::Paragraph => {
            for child in node.children() {
                walk_nodes(child, out, root_dir, diagrams_dir);
            }
            out.push_str("\n\n");
        }
        NodeValue::Text(t) => {
            out.push_str(&escape_typst(t));
        }
        NodeValue::SoftBreak => {
            out.push(' ');
        }
        NodeValue::LineBreak => {
            out.push_str("\\\n");
        }
        NodeValue::List(_) => {
            for child in node.children() {
                walk_nodes(child, out, root_dir, diagrams_dir);
            }
            out.push_str("\n");
        }
        NodeValue::Item(_) => {
            out.push_str("- ");
            for child in node.children() {
                // Inline the paragraph content directly to avoid the trailing \n\n
                // that Paragraph normally emits, which creates excessive spacing in lists.
                if matches!(&child.data.borrow().value, NodeValue::Paragraph) {
                    for inline in child.children() {
                        walk_nodes(inline, out, root_dir, diagrams_dir);
                    }
                    out.push('\n');
                } else {
                    walk_nodes(child, out, root_dir, diagrams_dir);
                }
            }
        }
        NodeValue::Strong => {
            out.push_str("#strong[");
            for child in node.children() {
                walk_nodes(child, out, root_dir, diagrams_dir);
            }
            out.push_str("]");
        }
        NodeValue::Emph => {
            out.push_str("#emph[");
            for child in node.children() {
                walk_nodes(child, out, root_dir, diagrams_dir);
            }
            out.push_str("]");
        }
        NodeValue::Table(t) => {
            let col_count = t.alignments.len();
            out.push_str(&format!(
                "#table(columns: ({}), stroke: 0.5pt, inset: 6pt, fill: (x, y) => if y == 0 {{ luma(240) }} else if calc.even(y) {{ luma(252) }},\n",
                vec!["1fr"; col_count].join(", ")
            ));
            for child in node.children() {
                walk_nodes(child, out, root_dir, diagrams_dir);
            }
            out.push_str(")\n\n");
        }
        NodeValue::TableRow(is_header) => {
            if *is_header {
                out.push_str("  table.header(\n");
            }
            for child in node.children() {
                walk_nodes(child, out, root_dir, diagrams_dir);
            }
            if *is_header {
                out.push_str("  ),\n");
            }
        }
        NodeValue::TableCell => {
            out.push_str("    [");
            for child in node.children() {
                walk_nodes(child, out, root_dir, diagrams_dir);
            }
            out.push_str("],\n");
        }
        NodeValue::Code(c) => {
            // Insert zero-width spaces (U+200B) after common separators so long
            // inline-code tokens (filenames, paths) can wrap inside table cells.
            let breakable: String = c.literal.chars().flat_map(|ch| {
                if matches!(ch, '_' | '-' | '.' | '/' | '\\') {
                    vec![ch, '\u{200B}']
                } else {
                    vec![ch]
                }
            }).collect();
            let max_ticks = count_max_backticks(&breakable);
            let fence = "`".repeat(max_ticks + 1);
            if breakable.starts_with('`') || breakable.ends_with('`') {
                out.push_str(&format!("{} {} {}", fence, breakable, fence));
            } else {
                out.push_str(&format!("{}{}{}", fence, breakable, fence));
            }
        }
        NodeValue::ThematicBreak => {
            out.push_str("#line(length: 100%, stroke: 0.5pt)\n\n");
        }
        NodeValue::Link(link) => {
            let url = escape_typst(&link.url);
            out.push_str(&format!("#link(\"{url}\")["));
            for child in node.children() {
                walk_nodes(child, out, root_dir, diagrams_dir);
            }
            out.push(']');
        }
        NodeValue::Image(img) => {
            let src = &img.url;
            let alt = {
                let mut s = String::new();
                for child in node.children() {
                    collect_text(child, &mut s);
                }
                s
            };
            // Resolve to an absolute filesystem path so it works regardless
            // of where the .typ source lives.
            let resolved = if src.starts_with("http://") || src.starts_with("https://") {
                src.clone()
            } else {
                root_dir.join(src).display().to_string()
            };
            if alt.is_empty() {
                out.push_str(&format!("#align(center, image(\"{resolved}\", width: 80%))\n\n"));
            } else {
                out.push_str(&format!(
                    "#figure(image(\"{resolved}\", width: 80%), caption: [{}])\n\n",
                    escape_typst(&alt)
                ));
            }
        }
        NodeValue::CodeBlock(c) => {
            if c.info == "mermaid" || c.info == "svgbob" {
                let svg = if c.info == "mermaid" {
                    match diagrams::render_mermaid(&c.literal) {
                        Ok(s) => Some(s),
                        Err(e) => {
                            eprintln!("Mermaid error: {}", e);
                            None
                        }
                    }
                } else {
                    Some(diagrams::render_svgbob(&c.literal))
                };

                if let Some(svg_content) = svg {
                    let _ = fs::create_dir_all(diagrams_dir);
                    let filename = format!("{}.svg", Uuid::new_v4());
                    let filepath = diagrams_dir.join(&filename);
                    if fs::write(&filepath, svg_content).is_ok() {
                        out.push_str(&format!(
                            "#align(center, box(image(\"{}\", width: 60%, height: 8cm, fit: \"contain\")))\n\n",
                            filepath.display()
                        ));
                    }
                } else {
                    out.push_str(&raw_block("", &c.literal, true));
                }
            } else {
                out.push_str(&raw_block(c.info.trim(), &c.literal, true));
            }
        }
        _ => {
            for child in node.children() {
                walk_nodes(child, out, root_dir, diagrams_dir);
            }
        }
    }
}

/// Collects plain text from a subtree (used for image alt text).
fn collect_text<'a>(node: &'a AstNode<'a>, out: &mut String) {
    if let NodeValue::Text(t) = &node.data.borrow().value {
        out.push_str(t);
    }
    for child in node.children() {
        collect_text(child, out);
    }
}

/// Counts the maximum run of consecutive backticks in a string.
fn count_max_backticks(s: &str) -> usize {
    let mut max = 0usize;
    let mut cur = 0usize;
    for c in s.chars() {
        if c == '`' {
            cur += 1;
            if cur > max {
                max = cur;
            }
        } else {
            cur = 0;
        }
    }
    max
}

/// Wraps content in a Typst raw block with a fence long enough to avoid
/// any backtick sequence inside the content. If `with_block` is true,
/// wraps in a styled #block(…)[…].
fn raw_block(lang: &str, content: &str, with_block: bool) -> String {
    let content = content.trim_end_matches('\n');
    let max_ticks = count_max_backticks(content);
    let fence = "`".repeat(max_ticks.max(2) + 1);
    if with_block {
        format!(
            "#block(fill: luma(245), inset: 8pt, radius: 4pt, width: 100%)[{}{}\n{}\n{}]\n\n",
            fence, lang, content, fence
        )
    } else {
        format!("{}{}\n{}\n{}", fence, lang, content, fence)
    }
}

/// Escapes characters that have special meaning in Typst markup mode.
fn escape_typst(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for c in s.chars() {
        match c {
            '\\' | '#' | '$' | '@' | '*' | '_' | '`' | '<' | '~' => {
                out.push('\\');
                out.push(c);
            }
            _ => out.push(c),
        }
    }
    out
}
