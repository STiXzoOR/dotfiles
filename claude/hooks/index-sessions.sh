#!/bin/bash
# Auto-index QMD sessions after Claude Code session ends
# Extracts recent sessions to vault and updates QMD index

VAULT_DIR="${VAULT_DIR:-$HOME/Vault}"
PYTHON="$HOME/.claude/skills/recall/.venv/bin/python3"
EXTRACT_SCRIPT="$HOME/.claude/skills/recall/scripts/extract-sessions.py"
LOG_FILE="$HOME/.claude/hooks/index-sessions.log"

# Rotate log if > 1MB
if [[ -f "$LOG_FILE" ]] && [[ $(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null) -gt 1048576 ]]; then
  tail -n 500 "$LOG_FILE" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE"
fi

# Extract last 3 days of sessions
if [[ -x "$PYTHON" ]] && [[ -f "$EXTRACT_SCRIPT" ]]; then
  "$PYTHON" "$EXTRACT_SCRIPT" --days 3 --output "$VAULT_DIR/Claude-Sessions" >> "$LOG_FILE" 2>&1
fi

# Update QMD index (fast — only processes changed files)
if command -v qmd &>/dev/null; then
  timeout 60 qmd update >> "$LOG_FILE" 2>&1
fi
