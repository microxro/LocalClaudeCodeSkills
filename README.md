# testing-will-things-work

Portable [Claude Code](https://claude.com/claude-code) skills, adapted for a
**local AI model** running behind Claude Code (Ollama, LM Studio, vLLM,
llama.cpp, or any Anthropic/OpenAI-compatible local endpoint) — no paid
Anthropic API required. This is a fork of
[`microxro/ClaudeCodeSkills`](https://github.com/microxro/ClaudeCodeSkills);
the content is the same idea, with the parts that assumed a paid multi-model
API (opus/sonnet/haiku tiering, unlimited parallel dispatch) rewritten for a
single local model with real hardware limits.

## What's here

- **`tree/` — `/tree`**: decompose a large or multi-part build into a verified
  task tree, split the optimal amount — wide enough to parallelize *within
  what your local model can actually run concurrently*, never wider — dispatch
  independent pieces to subagents on your local model, and refuse to declare
  it done until every piece is implemented, self-tested by its own worker,
  re-verified by you against the merged code, and integration-checked
  together. No model tiers here — difficulty classification instead drives
  gate rigor and how you respond to repeated failure, since there's no bigger
  model to escalate a stuck leaf to.

- **`taste/` — `/taste`**: apply practitioner judgment instead of
  generic-model defaults when creating or critiquing anything real — ground
  in the actual job/audience/exemplar, choose the right shape, rank by
  impact, use only source-backed specifics, commit to one recommendation,
  then subtract and quality-gate. Includes domain guidance for code, UI,
  documents, data, systems, and app/site deployment (with reference
  checklists for App Store, Play Store, and Vercel submission). This one
  doesn't depend on model tiering and is unchanged from the upstream skill.

- **`graph/` — `/graph`**: build and query a persistent, confidence-tagged
  knowledge graph of a repository (files, classes, functions, imports,
  calls, inheritance) instead of rediscovering its structure from scratch on
  every question — real AST parsing for Python, honestly-labeled heuristic
  extraction for other languages, god-node/community detection, a
  self-contained HTML visualization, and an optional SessionStart hook to
  keep it built automatically. Pure Python/stdlib, no LLM calls at all, so
  it works identically with a local model or the hosted API.

Each skill is a standard `SKILL.md` (+ `references/`, and for `graph/`,
`scripts/`) — nothing here depends on the others, install any subset.

## Why a separate version for local models

The upstream `/tree` skill assumes you can dispatch a wide wave of parallel
subagents, each routed to a different Anthropic model (opus for hard work,
sonnet for standard work, haiku for boilerplate) via paid API calls. Running
Claude Code against a single local model changes both halves of that:

- **No tiers.** There's one model. Difficulty classification here instead
  controls how many gates a leaf gets and how much you scrutinize its
  worker's self-report — a local model is more likely to claim a passing
  test it never actually ran, so re-verification matters even more than in
  the hosted version.
- **No free concurrency.** A single local inference server has a real,
  usually small, number of requests it can serve well at once. Dispatching
  a large "wave" the way the hosted skill does just queues workers behind
  each other, or degrades response quality under load. `/tree` here caps
  wave width at your actual local concurrency instead of at how many leaves
  happen to be ready.

`/taste` and `/graph` don't make model-tiering or parallel-dispatch
assumptions upstream, so they're included unchanged.

## Install

### Option A: as a plugin marketplace

This repo is a Claude Code plugin marketplace (`.claude-plugin/marketplace.json`
at the root, one plugin per skill). Add it and install what you want:

```bash
claude plugin marketplace add microxro/Testing-will-things-work
/plugin install tree      # or taste, or graph
```

### Option B: clone and copy

Clone the repo, then either run the installer or copy the folders by hand.

```bash
git clone <this-repo-url>
cd Testing-will-things-work
./install.sh                              # -> ~/.claude/skills (personal, every project)
./install.sh /path/to/project/.claude/skills   # -> a single project instead
```

Or by hand:

```bash
cp -r tree taste graph ~/.claude/skills/
```

That's it — no build step, no dependencies beyond Python 3 (stdlib only,
used by `/graph`'s scripts) and `git`. New Claude Code sessions will see
`/tree`, `/taste`, and `/graph` in their skill list, whether Claude Code is
pointed at a local model or the hosted API.

### Optional: `/graph`'s auto-build hook

`graph/scripts/session_start_hook.py` will, if wired into
`~/.claude/settings.json` as a `SessionStart` hook, automatically build or
refresh a repo's knowledge graph at the start of any session in a git repo
with enough source files to be worth it, and tell the session to consult it
before broad grepping. This is opt-in and not registered by `install.sh` —
see the snippet it prints at the end, or `graph/SKILL.md`, for the exact
`settings.json` stanza to add.

## Updating

Pull the latest version of this repo, then re-run `install.sh` — it
overwrites the previous copy of each skill directory.

## License

MIT — see [LICENSE](LICENSE).
