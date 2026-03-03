When starting a task that involves debugging, architecture decisions, or implementing something you've worked on before — use QMD MCP to search past sessions first.

Example lookback triggers:

- "Fix the X bug" → search for past fixes related to X
- "Implement Y feature" → search for past discussions about Y
- "How did we do Z?" → search sessions + notes

Quick search pattern:

1. `qmd_search` with collection "sessions" for exact keyword matches
2. If no results, try `qmd_vector_search` for semantic matches
3. Summarize relevant findings before proceeding
