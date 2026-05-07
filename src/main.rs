use anyhow::{Context, Result};
use clap::Parser;
use std::path::{Path, PathBuf};
use std::fs;
use std::process::Command;

mod markdown;
mod diagrams;

#[derive(Parser)]
#[command(author, version, about, long_about = None)]
struct Cli {
    /// Input Markdown file
    input: PathBuf,

    /// Output PDF file
    #[arg(short, long)]
    output: Option<PathBuf>,

    /// Watch for changes
    #[arg(short, long)]
    watch: bool,

    /// Document language (e.g. en, ru, de)
    #[arg(long, default_value = "en")]
    lang: String,

    /// Document font
    #[arg(long, default_value = "PT Sans")]
    font: String,

    /// Path to typst binary (defaults to ./typst-bin, then typst in PATH)
    #[arg(long)]
    typst_bin: Option<String>,
}

#[derive(Clone)]
struct ConversionConfig {
    lang: String,
    font: String,
    typst_bin: String,
}

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();

    let input_path = cli.input;
    let output_path = cli.output.unwrap_or_else(|| {
        let mut p = input_path.clone();
        p.set_extension("pdf");
        p
    });

    let typst_bin = cli.typst_bin.unwrap_or_else(|| {
        if Path::new("./typst-bin").exists() {
            "./typst-bin".to_string()
        } else {
            "typst".to_string()
        }
    });

    let config = ConversionConfig {
        lang: cli.lang,
        font: cli.font,
        typst_bin,
    };

    if cli.watch {
        watch_mode(&input_path, &output_path, config).await?;
    } else {
        run_conversion(&input_path, &output_path, &config)?;
    }

    Ok(())
}

fn run_conversion(input_path: &Path, output_path: &Path, config: &ConversionConfig) -> Result<()> {
    println!("Reading {}...", input_path.display());

    let abs_input = fs::canonicalize(input_path)
        .with_context(|| format!("Failed to resolve path {}", input_path.display()))?;
    let root_dir = abs_input
        .parent()
        .ok_or_else(|| anyhow::anyhow!("Input file has no parent directory"))?;

    // All intermediates (Typst source + diagram SVGs) live in system temp.
    // Per-process unique dir → safe for concurrent runs and watch mode.
    let tmp_dir = std::env::temp_dir().join(format!(
        "md2pdf-{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or(0)
    ));
    fs::create_dir_all(&tmp_dir)?;
    let diagrams_dir = tmp_dir.join("diagrams");

    let md_content = fs::read_to_string(input_path)
        .with_context(|| format!("Failed to read {}", input_path.display()))?;

    for w in markdown::lint(&md_content) {
        eprintln!("warning: {w}");
    }

    println!("Converting to Typst (AST mode)...");
    let typst_source = markdown::convert_to_typst(
        &md_content,
        &config.lang,
        &config.font,
        root_dir,
        &diagrams_dir,
    );

    let typst_file = tmp_dir.join("main.typ");
    fs::write(&typst_file, typst_source)?;
    println!("Done.");

    println!("Rendering to PDF...");

    // --root "/" lets typst access both the temp .typ file and user images
    // at their absolute paths. Acceptable for a local CLI tool.
    let status = Command::new(&config.typst_bin)
        .arg("compile")
        .arg(&typst_file)
        .arg(output_path)
        .arg("--root")
        .arg("/")
        .status()
        .with_context(|| format!("Failed to run typst binary '{}'", config.typst_bin))?;

    // Always clean up temp regardless of success/failure.
    let _ = fs::remove_dir_all(&tmp_dir);

    if status.success() {
        println!("Success! PDF saved to {}", output_path.display());
    } else {
        return Err(anyhow::anyhow!("Typst compilation failed."));
    }

    Ok(())
}

async fn watch_mode(input_path: &Path, output_path: &Path, config: ConversionConfig) -> Result<()> {
    println!("Entering watch mode for {}...", input_path.display());
    let mut last_modified = fs::metadata(input_path)?.modified()?;

    loop {
        let current_modified = fs::metadata(input_path)?.modified()?;
        if current_modified != last_modified {
            println!("File changed. Re-rendering...");
            let input = input_path.to_path_buf();
            let output = output_path.to_path_buf();
            let cfg = config.clone();
            if let Err(e) = tokio::task::spawn_blocking(move || run_conversion(&input, &output, &cfg)).await? {
                eprintln!("Error: {}", e);
            }
            last_modified = current_modified;
        }
        tokio::time::sleep(std::time::Duration::from_millis(500)).await;
    }
}
