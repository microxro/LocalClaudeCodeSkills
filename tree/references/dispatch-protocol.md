# Dispatching parallel workers and merging their results (local-model edition)

## Before dispatching a wave

For every leaf that's currently READY (pending, no open `blockedBy`, no owner):

1. Confirm its `owner_paths` don't overlap any other leaf you're about to dispatch in
   this same wave. If two READY leaves genuinely need to touch the same file (a
   shared config, a shared schema), don't dispatch them together — either sequence
   them, or fold them into one leaf so one worker owns the whole overlapping area.
2. Confirm its gates are written (`{id, check, expect}` for each).
3. Confirm its `difficulty` is set, so you know how much scrutiny and how many gates
   it needs (there's no model tier to route it to — see below).
4. Confirm the wave's total size does not exceed what your local model server can
   actually run concurrently without queuing, truncating, or degrading. If you don't
   know that number, default to 1-2 concurrent dispatches and only widen once you've
   confirmed the setup holds up.

Before accepting the wave as final, do one more pass over the *whole remaining
tree*, not just the leaves that happen to be READY right now: is there a `blockedBy`
edge anywhere that only exists because you didn't pin an interface? See "Widening a
wave with interface contracts" below — resolving even one of those can move a leaf
into this wave, concurrency permitting.

## Widening a wave with interface contracts

The most common reason a tree ends up mostly serial is treating "leaf B calls
something leaf A builds" as "leaf B must wait for leaf A to finish." Usually B only
needs to know the *shape* of what A builds — a function signature, a return type, a
CLI's output format, an API's request/response schema — not A's finished, tested
implementation. When that's true, don't serialize:

1. **Pin the interface yourself**, as the orchestrator, before dispatching either
   leaf — a few lines is usually enough (e.g. "`compute_stats(text: str) -> dict`
   returning `{"total": int, "unique": int, "frequencies": dict}`"). This becomes
   part of both leaves' briefs.
2. **Dispatch both leaves in the same wave, if your concurrency budget allows it**,
   each told to build against the pinned interface. Leaf B either imports a stub
   matching the interface for its own tests, or (if its owner scope makes that
   awkward) writes its tests against the interface description and you let the real
   integration gate confirm the fit once both are merged.
3. **Let the integration gate be the safety net.** This is exactly what section 8 of
   SKILL.md exists for — if A's real implementation drifts from the interface you
   pinned, that's a normal integration-gate failure, diagnosed and fixed like any
   other, not a sign that parallelizing was a mistake.

This only works when the interface is genuinely stable enough to pin up front, and
when you actually have a free concurrency slot to dispatch both at once — otherwise
run them as two back-to-back single dispatches against the same pinned interface,
which still saves you the serialization risk of one leaf guessing at the other's
undocumented shape. It never overrides the no-overlap rule: pinning an interface is
about *dependency*, not about permission to touch the same file.

## The dispatch call

For each leaf, call the `Agent` tool with:

- No `model` parameter to choose between tiers — every leaf runs on the same local
  model. Difficulty (`metadata.difficulty`) instead tells you how many gates to
  write and how much to scrutinize the result, per SKILL.md's table.
- `isolation: "worktree"` — this gives the worker its own git worktree and branch,
  so it's physically incapable of stepping on another in-flight leaf's uncommitted
  work even if `owner_paths` turned out to be misjudged.
- Fire only as many dispatches in the same message as your local server can
  genuinely run without degrading — sending N `Agent` calls at once is not free
  parallelism here the way it is against a hosted multi-model API; it's N requests
  competing for one machine's inference capacity. If that number is 1, dispatch one
  at a time and treat "the wave" as a short queue you work through in order rather
  than a burst.
- If this is a retry after a failure, don't reach for a bigger model — there isn't
  one. Sharpen the prompt with the specific failure observed, narrow the leaf, or
  hand-write the hard part yourself before redispatching (see SKILL.md's failure
  handling section).

## What to put in the worker's prompt

The worker has no memory of this conversation — brief it like a capable colleague
who just walked in. Keep the prompt itself tight and concrete: a local model is more
likely to lose track of instructions buried in a long, meandering brief than a large
hosted one, so favor short, explicit, numbered instructions over prose. Include,
concretely:

- **The leaf's requirement**, stated plainly and specifically — not just a restated
  task title, but not padded with unnecessary framing either.
- **Its `owner_paths`** — explicit instruction to touch only those files/paths, and
  not to "helpfully" fix or refactor things outside that scope.
- **Its gates verbatim** — every CHECK and EXPECT, stated as literally as possible.
- **The self-verification requirement, stated plainly and repeated if the leaf is
  hard**: implement the leaf, then actually run every one of its gates via Bash,
  look at the real output, and only report success for gates it just watched pass.
  If a gate fails, diagnose (real defect vs. bad gate vs. environment issue — see
  `gate-design.md`), fix the actual problem, and re-run before reporting back. If it
  genuinely cannot get a gate to pass, it must say so explicitly with what it tried
  and why it's stuck — never report a guessed or hoped-for PASS. Local models skip
  this step under pressure more often than large hosted ones, so don't assume it's
  understood from a single mention — make it unambiguous.
- **A narrower ask than you'd give a larger model, when the leaf is hard.** If a
  requirement is genuinely complex, consider breaking it into smaller sequential
  instructions within the same prompt, or pre-writing the trickiest part (a
  function signature, a tricky algorithm's skeleton) yourself so the worker's job is
  filling in a bounded gap rather than inventing the whole design.
- **What to report back**: for each gate, the exact command it ran and the real
  output/exit code it saw — not a paraphrase. This is what lets you sanity-check its
  claim before you re-run anything yourself.

A worker that implements but never runs its own gates has done half the job. A
worker that reports "should work" without having executed anything has told you
nothing you didn't already know.

## When a worker's agent call completes

You'll get the result back with the worktree path and branch name. Do this, in
order — don't skip to "mark it VERIFIED because the report looked confident":

1. **Read the worker's report.** Does it claim every gate passed with real
   command/output evidence? If it reported a failure or couldn't verify something,
   that's the leaf's actual status right now — go to failure handling (SKILL.md),
   don't paper over it.
2. **Merge its branch** into your integration branch: `git merge <branch>`. A clean
   merge is itself a small piece of evidence that the scoping was right. A conflict
   means either two leaves' scopes overlapped after all, or the worker touched files
   outside its declared `owner_paths` — figure out which before resolving.
3. **Re-run the leaf's gates yourself**, against the now-merged tree — actually
   execute the CHECK commands via Bash again. This is the step that makes VERIFIED
   mean something beyond "a worker said so," and it matters more here than with a
   large hosted model: catches both a worker that misjudged its own output and a
   merge that broke something neither side could see in isolation.
4. **Only now** set the task `completed` with `metadata.state: "VERIFIED"` and
   `metadata.evidence` recording what you ran and saw. If your re-run disagrees with
   the worker's report, treat that as a real finding (see below) — don't just accept
   whichever answer is more convenient.
5. **Update the dependency graph.** Any leaf that was WAITING on this one may now be
   READY — check its `blockedBy` and, if clear and a concurrency slot is free,
   dispatch it next rather than waiting for the rest of the current wave to finish
   (rolling dispatch).

## If your re-verification disagrees with the worker

If the worker reported PASS but your re-run fails: something changed between the
worker's run and yours (most likely the merge itself, or a worker that misread its
own output — more common on a local model than a large hosted one). Diagnose which —
check whether the failure implicates code the merge touched versus code the worker
never saw touched at all — fix the real cause, and re-run. Don't quietly mark it
VERIFIED anyway because "the worker tried its best."

## Merge order across a wave

Merge completed leaves back one at a time as they finish, not all at once at the end
of a wave — this keeps each merge small and each `git merge` conflict (if any)
attributable to exactly one leaf, rather than a tangle of several at once. This is
easy to do naturally in the local-model setup, since waves here are usually small
and often sequential anyway.
