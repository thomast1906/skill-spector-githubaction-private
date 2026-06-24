# skill-spector-githubaction-private

GitHub Actions workflow to run [NVIDIA SkillSpector](https://github.com/NVIDIA/SkillSpector) — a security scanner for AI agent skills.

## Setup

1. Add your OpenAI API key as a repository secret named **`OPENAI_API_KEY`**
   - Go to **Settings → Secrets and variables → Actions → New repository secret**

2. Enable **GitHub Code Scanning** (Settings → Security → Code scanning) to view SARIF results in the Security tab.

## Usage

The workflow runs automatically on:
- Push / PR to `main`
- Every Monday at 06:00 UTC

Or trigger it manually via **Actions → SkillSpector Security Scan → Run workflow**, where you can optionally supply a custom target (git URL, zip, or file path) and toggle LLM analysis.

## Outputs

| Artifact | Description |
|---|---|
| `skillspector-results.sarif` | Uploaded to GitHub Code Scanning |
| `skillspector-report.md` | Markdown report attached to the workflow run |
| Job Summary | Markdown report printed inline in the Actions UI |

## LLM analysis

When `OPENAI_API_KEY` is set, SkillSpector performs a two-stage scan:
1. Fast static analysis (68 patterns across 17 categories)
2. LLM semantic evaluation via OpenAI (`gpt-5.4` default)

Omit the secret or select `use_llm: false` in the manual trigger to run static-only.