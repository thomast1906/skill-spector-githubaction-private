#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────
# SkillSpector local scan via Docker
# Usage: ./scan-local.sh [OPTIONS] [TARGET]
#
# TARGET  Git URL, file path, or directory to scan (default: current repo)
# ─────────────────────────────────────────────

IMAGE_NAME="skillspector"
SKILLSPECTOR_REPO="https://github.com/NVIDIA/skillspector.git"
BUILD_DIR="${TMPDIR:-/tmp}/skillspector-src"
NO_LLM=false
REBUILD=false
FORMAT="markdown"  # terminal | json | markdown | sarif
OUTPUT_FILE=""

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS] [TARGET]

  TARGET              What to scan: git URL, zip, file, or local path (default: .)

Options:
  --no-llm            Skip LLM analysis (static scan only, no API key needed)
  --rebuild           Force rebuild of the Docker image
  --format FORMAT     Output format: terminal | json | markdown | sarif (default: markdown)
  --output FILE       Save report to FILE (default: print to stdout)
  -h, --help          Show this help

Environment:
  OPENAI_API_KEY      OpenAI API key (required for LLM analysis)
  .env                Sourced automatically if present (put OPENAI_API_KEY=sk-... there)

Examples:
  ./scan-local.sh                                   # scan this repo, LLM on
  ./scan-local.sh --no-llm                          # static only
  ./scan-local.sh https://github.com/user/my-skill  # scan a remote skill
  ./scan-local.sh --format sarif --output out.sarif # save SARIF report
EOF
}

# ── Parse arguments ───────────────────────────
TARGET=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-llm)   NO_LLM=true; shift ;;
    --rebuild)  REBUILD=true; shift ;;
    --format)   FORMAT="$2"; shift 2 ;;
    --output)   OUTPUT_FILE="$2"; shift 2 ;;
    -h|--help)  usage; exit 0 ;;
    -*)         echo "Unknown option: $1"; usage; exit 1 ;;
    *)          TARGET="$1"; shift ;;
  esac
done

# ── Load .env if present ──────────────────────
if [[ -f .env ]]; then
  echo "📄 Loading .env..."
  set -o allexport
  # shellcheck disable=SC1091
  source .env
  set +o allexport
fi

# ── Pre-flight checks ─────────────────────────
if ! docker info &>/dev/null; then
  echo "❌ Docker is not running. Please start Docker Desktop and retry."
  exit 1
fi

# ── Build Docker image if needed ──────────────
if [[ "$REBUILD" == "true" ]] || ! docker image inspect "$IMAGE_NAME" &>/dev/null; then
  echo "🔨 Building SkillSpector Docker image..."
  if [[ -d "$BUILD_DIR" ]]; then
    echo "   Updating existing clone..."
    git -C "$BUILD_DIR" pull --quiet
  else
    echo "   Cloning SkillSpector..."
    git clone --quiet "$SKILLSPECTOR_REPO" "$BUILD_DIR"
  fi
  docker build --quiet -t "$IMAGE_NAME" "$BUILD_DIR"
  echo "✅ Image built: $IMAGE_NAME"
else
  echo "✅ Using cached Docker image: $IMAGE_NAME (use --rebuild to refresh)"
fi

# ── Resolve scan target ───────────────────────
# If TARGET is empty or a local path, mount it; if it's a URL, pass directly.
DOCKER_ARGS=(run --rm)
SCAN_PATH=""

if [[ -z "$TARGET" ]]; then
  # Default: scan current directory
  DOCKER_ARGS+=(-v "$PWD:/scan")
  SCAN_PATH="."
elif [[ "$TARGET" =~ ^https?:// || "$TARGET" =~ ^git@ ]]; then
  # Remote URL — no mount needed
  DOCKER_ARGS+=(-v "$PWD:/scan")
  SCAN_PATH="$TARGET"
else
  # Local path — resolve to absolute and mount
  ABS_TARGET="$(cd "$(dirname "$TARGET")" && pwd)/$(basename "$TARGET")"
  DOCKER_ARGS+=(-v "$ABS_TARGET:/scan_target:ro" -v "$PWD:/scan")
  SCAN_PATH="/scan_target"
fi

# ── LLM credentials ───────────────────────────
if [[ "$NO_LLM" == "false" ]]; then
  if [[ -z "${OPENAI_API_KEY:-}" ]]; then
    echo "⚠️  OPENAI_API_KEY not set — falling back to static-only scan."
    echo "   Set it in your environment or add it to a .env file."
    NO_LLM=true
  else
    DOCKER_ARGS+=(-e SKILLSPECTOR_PROVIDER="${SKILLSPECTOR_PROVIDER:-openai}" -e OPENAI_API_KEY="$OPENAI_API_KEY")
    [[ -n "${OPENAI_BASE_URL:-}" ]]      && DOCKER_ARGS+=(-e OPENAI_BASE_URL="$OPENAI_BASE_URL")
    [[ -n "${SKILLSPECTOR_MODEL:-}" ]]   && DOCKER_ARGS+=(-e SKILLSPECTOR_MODEL="$SKILLSPECTOR_MODEL")
    echo "🔑 LLM analysis enabled (${SKILLSPECTOR_PROVIDER:-openai}${OPENAI_BASE_URL:+ → $OPENAI_BASE_URL}${SKILLSPECTOR_MODEL:+, model: $SKILLSPECTOR_MODEL})"
  fi
fi

# ── Build scan command ────────────────────────
SCAN_CMD=(scan "$SCAN_PATH")
[[ "$NO_LLM" == "true" ]] && SCAN_CMD+=(--no-llm)
SCAN_CMD+=(--format "$FORMAT")

# If writing to a file, pass the filename as-is — container WORKDIR is /scan (mounted to $PWD)
if [[ -n "$OUTPUT_FILE" ]]; then
  SCAN_CMD+=(--output "$OUTPUT_FILE")
fi

# ── Run ───────────────────────────────────────
echo ""
echo "🔍 Scanning: ${TARGET:-(current directory)}"
echo "─────────────────────────────────────────"
SCAN_EXIT=0
docker "${DOCKER_ARGS[@]}" "$IMAGE_NAME" "${SCAN_CMD[@]}" || SCAN_EXIT=$?

if [[ -n "$OUTPUT_FILE" ]]; then
  echo ""
  if [[ -f "$OUTPUT_FILE" ]]; then
    echo "📄 Report saved to: $PWD/$OUTPUT_FILE"
  else
    echo "⚠️  Output file not found at $PWD/$OUTPUT_FILE"
    echo "   Try re-running with --no-llm if LLM errors caused an early exit."
  fi
fi

exit $SCAN_EXIT
