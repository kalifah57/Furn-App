# Scoring rubric

Furniture has **no single correct answer**, so scoring is **not** exact-match. A
case is graded by an objective gate + a graded quality score.

## Per case
```
hard_pass      = every expected_constraints check holds            (objective, auto)
machine_met    = fraction of acceptance_criteria.machine that hold (objective, auto)
human_met      = fraction of acceptance_criteria.human the expert marked met (human)
criteria_met   = (machine_met + human_met) / 2
stars          = expert 1..5

case_score = hard_pass ? (0.6 · criteria_met + 0.4 · stars/5) : 0
```
- **Invariant** cases: only `hard_pass` matters (no acceptance criteria, no expert). A failing invariant fails the run (non-zero exit) — the regression gate.
- **Canonical** cases: need at least one expert review to produce a `case_score`; until then the runner reports `pending`.

## Aggregate
```
benchmark_score = mean(case_score over scored canonical cases)   // 0..1
invariant_pass  = passing invariants / total invariants
```

## How it gates development
Record `benchmark_score` + `invariant_pass` before a change. After any change to
the engine (weights, ceilings, filters — or later, a new AI provider or
catalog): re-run. **Any drop is rejected** unless deliberately re-baselined with
a written reason. This is the asset that keeps decision quality from silently
regressing as the system grows.
