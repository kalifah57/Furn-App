# Scenario schema — one self-contained file per case

Each case is **one independent file** in `benchmark/scenarios/<id>.json` (so the
structure never changes at 200 or 500 cases). A scenario is the objective
*fixture*; the subjective expert judgment lives separately in
`benchmark/expert_reviews/` (one scenario can be judged by many experts over
time, and the fixture must stay frozen).

Every case carries the **four layers**:

| Layer | Field | Meaning |
|---|---|---|
| **1 · Input** | `input` | the user's situation as a `FurnishingProject` (+ `raw_quote` for real cases) |
| **2 · Expected Constraints** | `expected_constraints` | hard rules that MUST hold (budget, space, availability…). Violation ⇒ case score 0 |
| **3 · Expert Evaluation** | *(separate file in `expert_reviews/`)* | a furniture/interior expert's 1–5 rating + notes on the actual output |
| **4 · Acceptance Criteria** | `acceptance_criteria` | when the recommendation counts as "successful" — a machine-checkable subset + human-judged criteria |

```json
{
  "id": "c001-majlis-5000",
  "tier": "canonical",                 // "invariant" (objective) | "canonical" (real + expert)
  "split": "dev",                      // canonical only: "dev" (tune here) | "test" (held-out gate); ~70/30, frozen
  "title": "one-line summary",
  "source": "reddit:<permalink> | quora:<url> | interview:<id> | synthetic",
  "raw_quote": "the person's ACTUAL words (verbatim, Arabic)",
  "input": { /* FurnishingProject shape: locale, room, budget, style, items */ },
  "expected_constraints": [            // LAYER 2 — hard gate (see constraints/catalog.md)
    { "type": "in_stock" },
    { "type": "fits_room" },
    { "type": "within_total_budget" },
    { "type": "covers_category", "category": "sofa" }
  ],
  "acceptance_criteria": {             // LAYER 4
    "machine": [ { "type": "covers_category", "category": "rug" } ],
    "human":   [ "recommends a sofa that leaves walking space" ],
    "pass_threshold": 0.7
  }
}
```

Rules: `id` is unique and matches the filename. Files beginning with `_`
(e.g. `_TEMPLATE.json`) are ignored by the runner. `invariant` cases need no
expert review (pure hard gate); `canonical` cases need a matching
`expert_reviews/<id>.*.json` to be fully scored.
