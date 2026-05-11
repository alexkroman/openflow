#!/bin/bash
# Download the bundled LLM (~1.4 GB) into the Xcode project's resources.
# Run once before building. The destination is gitignored.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="$REPO_ROOT/App/OpenFlow/OpenFlow/Resources/Models/Qwen3.5-2B-OptiQ-4bit"

if [ -f "$TARGET/config.json" ]; then
  echo "Model already at $TARGET"
  exit 0
fi

mkdir -p "$TARGET"

if command -v huggingface-cli >/dev/null 2>&1; then
  CLI="huggingface-cli"
elif command -v hf >/dev/null 2>&1; then
  CLI="hf"
else
  cat <<EOF
HuggingFace CLI not found. Install with one of:
  pip install --upgrade 'huggingface_hub[cli]'
  brew install huggingface-cli
EOF
  exit 1
fi

echo "Downloading mlx-community/Qwen3.5-2B-OptiQ-4bit (~1.4 GB) to:"
echo "  $TARGET"
"$CLI" download mlx-community/Qwen3.5-2B-OptiQ-4bit --local-dir "$TARGET"

echo "Done."
