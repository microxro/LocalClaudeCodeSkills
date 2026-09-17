#!/usr/bin/env bash
# Installs the skills in this repo into a Claude Code skills directory.
# Works the same whether Claude Code is pointed at a local model or the
# hosted Anthropic API — this only copies files.
#
# Usage:
#   ./install.sh                  # installs to ~/.claude/skills (personal, all projects)
#   ./install.sh /path/to/.claude/skills   # installs to a specific project instead
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="${1:-$HOME/.claude/skills}"

mkdir -p "$DEST"
for skill in tree taste graph; do
  rm -rf "${DEST:?}/$skill"
  cp -r "$SRC/$skill" "$DEST/$skill"
  echo "installed: $DEST/$skill"
done

cat <<'EOF'

Done. New sessions in this environment will see /tree, /taste, and /graph.

Note on /tree and local models: this fork's /tree skill assumes a single
local model with limited concurrency rather than the hosted API's
opus/sonnet/haiku tiers. Before running a large /tree task, know how many
concurrent requests your local inference server (Ollama, LM Studio, vLLM,
etc.) can actually handle well — the skill will ask you for this if it
isn't obvious, and will cap parallel dispatch at that number rather than
firing off every ready leaf at once.

Optional: the /graph skill includes a SessionStart hook script
(graph/scripts/session_start_hook.py) that auto-builds/refreshes a repo
knowledge graph when a session starts inside a large-enough git repo, and
tells the session to consult it. Copying the skill files here does NOT
register that hook — it's a separate, explicit step because it changes
every future session's startup behavior. To enable it, add this to
~/.claude/settings.json (merge with any existing "hooks" key, don't
overwrite it):

{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "python3 ~/.claude/skills/graph/scripts/session_start_hook.py",
            "timeout": 15,
            "statusMessage": "Checking for a repo knowledge graph..."
          }
        ]
      }
    ]
  }
}

After editing settings.json, run /hooks once (or start a new session) to
pick it up.
EOF
