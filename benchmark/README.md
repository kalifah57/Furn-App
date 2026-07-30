# Decision Benchmark — the project's golden yardstick

The single highest-leverage asset in this project. It measures **decision
quality** — does the engine, given a real furnishing situation, produce a
recommendation an expert (and a user) would accept? It is implementation-
independent, so it **survives** every later change: real AI, real catalog,
backend. Any engine change is measured against it; a change that lowers the
score is rejected.

> Not "does the engine run" — the engine already exists. **"Does the engine
> decide well."** And because furniture has **no single correct answer**
> (unlike MMLU), we do **not** grade `output == expected`. We grade against
> objective constraints + an expert rubric.

## Two tiers

| Tier | File | Scored how | Provenance | Purpose |
|---|---|---|---|---|
| **1 · Invariants** | `invariants.json` | **auto** (objective rules) | synthetic is fine here | regression gate on every change |
| **2 · Canonical** | `canonical.template.json` → `canonical.json` | **hard checks + expert rubric** | **must be REAL** (Reddit/Quora/interviews) | proves decisions are *good*, not just *legal* |

**Why the split:** invariants test physics/rules (fit, availability, budget
sanity, coverage, synonym mapping) — true regardless of taste, so synthetic
cases are legitimate there. Quality is a matter of taste, so those cases must
be **real** and labeled by an expert. A benchmark of invented "good" answers
would be a false idol.

## Scoring model
- **Invariant (Tier 1):** each case passes iff it violates **no** hard rule. The runner exits non-zero on any failure → usable as a CI gate.
- **Canonical (Tier 2):** `case_score = hard_pass ? (0.6·criteria_met + 0.4·stars/5) : 0`, where `criteria_met` is the fraction of the expert's `must_include`/`must_not_include` satisfied and `stars` is the expert's 1–5 rating. `benchmark_score = mean(case_score)`.

## Run the invariant tier now
From the repo root, on any machine with the Dart/Flutter SDK:

```bash
flutter pub get                       # one-time: resolves equatable + uuid
dart run benchmark/run_benchmark.dart # prints + writes invariants_report.md; exit≠0 on any failure
```

This uses the **existing** engine (`domain_engine`) — no Flutter, device, or
backend. It is the ~120-line scorer, not a new engine.

## Build the canonical tier (the real work)
1. **Collect ~12 real cases** from r/saudiarabia, r/interiordecorating, Quora, Facebook groups, or short interviews. Copy the person's actual words into `raw_quote`. *(This doubles as problem-validation: if people really post these, the problem is real.)*
2. Encode each as `input` (the `FurnishingProject` shape) in `canonical.json`.
3. Have a **furniture/interior expert** fill `expert` — acceptance criteria (`must_include` / `must_not_include`), the objective `hard_constraints`, and a quality-bar note. **Not** a single golden answer.
4. Run the engine on each, record `actual_output`, and let the expert score `criteria_met` + `stars`.
5. Grow toward **100** cases over time. Every case is permanent.

## Then, and only then: the user Trust Test
Reuse the **same** canonical cases with target users (desirability), instead of
building a separate test layer. Objective quality (expert) first; subjective
acceptance (user) second — they are different questions and this order keeps
them from being conflated.

## What this replaces
The earlier synthetic "trust test" (`tool/trust_test*`) is superseded: its
objective cases moved here as invariants; its taste-based cases were dropped
because inventing "good" answers is not evidence.
