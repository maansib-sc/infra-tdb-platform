set -euo pipefail

INFRA_DIR="/workspaces/Talking-db-SC/infra-tdb-platform"
WORKSPACE="/workspaces/Talking-db-SC"
MODULE_DIR="$WORKSPACE/module-talkingdb"

cd "$INFRA_DIR"

echo "▶ Cloning sibling repositories listed in local/repo.yaml"
make clone

echo "▶ Syncing repositories and installing Poetry dependencies (mode=git)"
make sync

if [[ -d "$MODULE_DIR" ]]; then
  if [[ ! -f "$MODULE_DIR/.env" && -f "$MODULE_DIR/.env.example" ]]; then
    echo "▶ Bootstrapping module-talkingdb/.env from .env.example"
    cp "$MODULE_DIR/.env.example" "$MODULE_DIR/.env"
  fi

  echo "▶ Pre-downloading spaCy en_core_web_md into module-talkingdb's venv"
  (cd "$MODULE_DIR" && poetry run python -m spacy download en_core_web_md) \
    || echo "⚠ spaCy model download failed; 'make local' will retry on first run"

  echo "▶ Installing git hooks in module-talkingdb"
  (cd "$MODULE_DIR" && make install-hooks) \
    || echo "⚠ git hooks install skipped"
fi

echo "▶ Generating .vscode/launch.json from sibling debugpy ports"
make debug-config || echo "⚠ debug-config skipped (no debugpy ports detected)"

echo "▶ Generating multi-root workspace file"
WORKSPACE_FILE="$WORKSPACE/talkingdb.code-workspace"
{
  echo '{'
  echo '  "folders": ['
  first=1
  for dir in "$WORKSPACE"/*/; do
    name="$(basename "$dir")"
    [[ -d "$dir/.git" ]] || continue
    if [[ $first -eq 1 ]]; then first=0; else echo ','; fi
    printf '    { "path": "%s" }' "$name"
  done
  echo
  echo '  ],'
  echo '  "settings": {}'
  echo '}'
} > "$WORKSPACE_FILE"
echo "  → $WORKSPACE_FILE"

echo "✔ Workspace ready. Run 'make local' from $INFRA_DIR to start the platform."
