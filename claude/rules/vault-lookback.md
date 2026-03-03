When starting a task that involves debugging, architecture decisions, or implementing something you've worked on before — use QMD MCP to search past sessions first.

Example lookback triggers:

- "Fix the X bug" → search for past fixes related to X
- "Implement Y feature" → search for past discussions about Y
- "How did we do Z?" → search sessions + notes

## Search Modes

Use the right search mode for the job:

1. **`qmd_search`** (~30ms) — BM25 keyword matching. Best for exact terms, error messages, file paths, function names. Start here.
2. **`qmd_vector_search`** (~2s) — Semantic/meaning-based. Finds related content even when vocabulary differs. Use when keyword search returns nothing.
3. **`qmd_deep_search`** (~10s) — Hybrid with auto-expansion and re-ranking. Most thorough. Use for broad questions or when you need comprehensive results.

## Collections

- `sessions` — Claude Code session transcripts (conversation history)
- `notes` — Obsidian vault (resources, projects, daily notes, decisions)

## Quick search pattern

1. `qmd_search` with collection "sessions" for exact keyword matches
2. If no results, `qmd_vector_search` for semantic matches
3. For broad questions, `qmd_deep_search` across both collections
4. Summarize relevant findings before proceeding

## Tips

- Use `minScore: 0.5` to filter low-confidence results
- Use `get` with file paths from search results to read full documents
- Search `notes` collection for durable knowledge (decisions, patterns)
- Search `sessions` collection for conversation context and debugging history
