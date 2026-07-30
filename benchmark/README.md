# Decision Benchmark — the project's permanent quality system

The single highest-leverage asset here. It measures **decision quality**: given a
real furnishing situation, does the engine produce a recommendation an expert
(and a user) would accept? It is implementation-independent, so it **survives**
every later change — a new AI provider, a real catalog, a backend. Every engine
change is measured against it; a change that lowers the score is rejected.

This is a **permanent subsystem**, not throwaway test files. It is designed as a
system first, then filled with cases gradually — so the structure never changes
at 200 or 500 cases.

## Layout
```
benchmark/
├── schema/            # the case + expert-review file formats (the 4 layers)
├── constraints/       # the reusable check library the runner understands
├── rubric/            # the scoring model (hard gate + criteria + stars → score)
├── scenarios/         # ONE self-contained file per case  (invariant + canonical)
├── expert_reviews/    # ONE file per (scenario × expert) — the human judgment
├── benchmark_runner.dart
└── reports/           # generated benchmark_report.md
```

## The four layers of every case
1. **Input** — the user's situation (`input`, + `raw_quote` for real cases).
2. **Expected Constraints** — hard rules that must hold (`expected_constraints`); violation ⇒ score 0.
3. **Expert Evaluation** — a furniture/interior expert's 1–5 rating + notes (a file in `expert_reviews/`).
4. **Acceptance Criteria** — when the recommendation is "successful" (`acceptance_criteria`: a machine-checkable subset + human-judged criteria).

See `schema/scenario.schema.md`, `constraints/catalog.md`, `rubric/scoring.md`.

## Two tiers
| Tier | Provenance | Scored | Purpose |
|---|---|---|---|
| **invariant** | synthetic OK | **auto** (hard gate only) | regression gate — must never fail |
| **canonical** | **must be REAL** (Reddit/Quora/interviews) | hard gate + expert rubric | proves decisions are *good*, not just *legal* |

12 invariant scenarios ship now. Canonical scenarios are added over time.

## Run it
From the repo root, on any machine with the Dart/Flutter SDK:
```bash
flutter pub get                          # one-time: resolves equatable + uuid
dart run benchmark/benchmark_runner.dart # prints + writes reports/benchmark_report.md
```
Uses the **existing** engine (`domain_engine`, pure Dart) — no Flutter, device,
or backend. Exits non-zero if any invariant fails.

## Add a case (the ongoing work)
1. Copy `scenarios/_TEMPLATE.json` → `scenarios/cNNN-slug.json`. Paste the real user's words into `raw_quote`; fill `input`, `expected_constraints`, `acceptance_criteria`. *(Collecting real cases doubles as problem-validation.)*
2. Run the benchmark to capture the engine's `actual_output` in the report.
3. Copy `expert_reviews/_TEMPLATE.json` → `expert_reviews/cNNN-slug.<expert>.json`; the expert fills `stars` + `human_criteria_met`.
4. Re-run — the case now contributes to `benchmark_score`.
5. Grow toward 100. Every case is permanent.

## Then: the user Trust Test
Reuse the **same** canonical scenarios with target users (desirability) instead
of building a separate layer. Objective expert quality first, subjective user
acceptance second — different questions, kept from being conflated.
