Before a task that involves debugging, an architecture decision, or something
you have worked on before, search past sessions and notes with the QMD MCP
server. It indexes the Obsidian vault and the exported Claude Code sessions.

Lookback triggers:

- "Fix the X bug" → search for past fixes related to X
- "Implement Y feature" → search for past discussions about Y
- "How did we do Z?" → search sessions and notes together

## Tools

The server exposes exactly four tools, listed below. An earlier version of
this file named three others with confident latency figures; none of them ever
existed, so anything that looks like a per-mode search tool is a hallucination
and calling it will fail.

- **`query`** — the unified search. One call runs keyword search, vector
  search and reranking, so it replaces the three-step ritual entirely.
- **`get`** — one document by path or docid (`#abc123`). Takes a line offset,
  as in `file.md:100`.
- **`multi_get`** — several documents at once, by glob (`journals/2025-05*.md`)
  or a comma-separated list.
- **`status`** — collection descriptions, paths and document counts.

## Using `query`

Pass `searches` as a list of typed sub-queries and always pass `intent`, which
disambiguates the query and improves the snippets you get back:

- `type: 'lex'` — BM25 keyword matching. Exact terms, error messages, file
  paths, function names.
- `type: 'vec'` — semantic. Finds related content when the vocabulary differs.
- `type: 'hyde'` — write what the answer would look like and search for that.
  Best for broad questions.

Combining types in one call beats running them one after another:

```
searches = [{ type: 'lex', query: 'fnm multishell' },
            { type: 'vec', query: 'why hooks cannot find node' }]
intent   = 'debugging a hook that cannot resolve a node binary'
```

Scope with the `collections` array.

## Collections

- `sessions` — exported Claude Code transcripts, written into the vault by the
  sync-claude-sessions hook. Search this for conversation context and
  debugging history.
- `notes` — the Obsidian vault: resources, projects, daily notes, decisions.
  Search this for durable knowledge.

## Tips

- `minScore: 0.5` filters low-confidence results.
- Follow a hit with `get` to read the whole document; file paths in results are
  relative to their collection.
- Results carry a `context` field describing the kind of content.
- Summarise what you found before acting on it.
