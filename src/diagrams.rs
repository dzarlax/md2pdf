use anyhow::Result;
use mermaid_rs_renderer::render as render_mermaid_internal;

pub fn render_mermaid(code: &str) -> Result<String> {
    // High-level render function returns Result<String, Error>
    render_mermaid_internal(code.trim()).map_err(|e| anyhow::anyhow!("Mermaid error: {}", e))
}

pub fn render_svgbob(code: &str) -> String {
    svgbob::to_svg(code)
}
