# Expert review schema — the human judgment layer

One file per (scenario × expert) in `benchmark/expert_reviews/<scenario_id>.<expert>.json`.
Kept separate from the scenario on purpose: the fixture is objective and frozen;
reviews are subjective, may come from several experts, and accrete over time.

```json
{
  "scenario_id": "c001-majlis-5000",   // must match a scenario id
  "expert": "aa",                       // reviewer initials/handle
  "reviewed_at": "2026-07-30",
  "engine_output_note": "paste the recommendations the expert actually judged (from reports/benchmark_report.md)",
  "stars": 4,                           // 1..5 overall quality
  "human_criteria_met": [               // one entry per acceptance_criteria.human item
    { "criterion": "recommends a sofa that leaves walking space", "met": true }
  ],
  "notes": "free-text justification"
}
```

Scoring (see `rubric/scoring.md`): only `canonical` cases with at least one
review are scored; multiple reviews of the same scenario can later be averaged
for inter-rater agreement.
