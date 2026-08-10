# Benchmark Pipeline — operator prompt (research · collect · tune · test)

Paste this to an agent (or a future session) to grow and defend the Decision
Benchmark. Run the four phases **in order**. The guardrails are absolute.

## Guardrails (non-negotiable)
- **Never fabricate** a case, a quote, a price, or a source. Every *canonical*
  case cites a **real, working source URL**, and `raw_quote` stays faithful to it.
- **Taste is judged by a human expert, never by the agent.** You may *draft*
  `acceptance_criteria`; you may not assign `stars`.
- The engine is **deterministic — there is no ML model.** "Tune" means adjust
  **rule parameters**, not train weights.
- Keep a **held-out TEST split you never tune against.**
- If a phase can't be done honestly (e.g. no real sources reachable), **STOP and
  say so** — do not fake output. *(This has already happened once: US-only web
  search returns SEO guidelines, not quote-able user cases — see
  `rubric/heuristics.md`. Collect real cases from real request threads instead.)*

## Phase 1 — Research (بحث)
**Goal:** find (a) real people describing *room + budget + style + needs*, and
(b) sourced design heuristics that define a "good" decision.
**Do:** WebSearch/WebFetch real request threads (r/DesignMyRoom, r/InteriorDesign,
Quora "help me furnish…"), and sourced measurements (clearances, sizing). Prefer
Gulf/Saudi context; accept global where local is unavailable.
**Output:** source URLs; sourced heuristics appended to `rubric/heuristics.md`
(cite every one).

## Phase 2 — Collect (جمع)
For each real post → `scenarios/cNNN-slug.json` (`tier: canonical`,
`split: dev|test`, ~70/30, **frozen at creation**): extract room/budget/style/
items into `input`, put the person's own words in `raw_quote`, set `source` to
the real URL. Draft `acceptance_criteria` (a machine subset from
`constraints/catalog.md` + human criteria from `rubric/heuristics.md`). Create an
`expert_reviews/…` stub for an expert to fill. **Do not invent inputs.**

## Phase 3 — Tune (تدريب · dev split ONLY)
No model training. Tune **rule parameters** — scoring weights
(`lib/domain_engine/recommendation/scoring.dart`), budget ceilings
(`budget_allocator.dart`), hard-limit factor + fit thresholds
(`constraint_engine.dart`) — to raise `benchmark_score` on the **dev** split.
After each change: `dart run benchmark/benchmark_runner.dart`. Keep a change only
if it **raises dev score AND fails zero invariants**. **Never inspect the test
split here.** Log each change + its dev-score delta.

## Phase 4 — Test (اختبار · held-out)
Run once on the **test** split for the honest, non-overfit number. That is the
reported `benchmark_score` and the regression gate. Any future engine / AI /
catalog change re-runs both splits; a **drop on test is rejected** unless
deliberately re-baselined with a written reason.

## Stop conditions
- Any **invariant** fails → stop, fix the engine, before tuning.
- **No real sources** reachable → stop; report; do not fabricate.
- **test ≪ dev** → overfitting; widen/rebalance cases before trusting the gate.
- Fewer than ~10 canonical cases → the score is indicative, not a gate yet.
