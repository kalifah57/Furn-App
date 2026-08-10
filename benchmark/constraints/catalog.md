# Constraint library — the reusable checks the runner understands

Shared, named checks (not per-case data). A scenario references them by `type`
in `expected_constraints` (hard gate) and in `acceptance_criteria.machine`
(graded). Implemented in `benchmark_runner.dart` → `_holds()`. Adding a new
check = one `case` in that switch + a row here.

| `type` | params | Passes when | Notes |
|---|---|---|---|
| `no_recommendations` | — | engine returns nothing | for "budget below floor" / impossible cases |
| `in_stock` | — | no recommended item is out-of-stock | availability sanity |
| `fits_room` | — | every recommended item physically fits (direct or rotated) | skipped if room has no dimensions |
| `within_total_budget` | — | no *individual* item costs more than the whole budget | skipped if no budget set |
| `covers_category` | `category` (bed·sofa·rug·table·lamp·storage) | ≥1 individual item of that category | requested-need coverage |
| `excludes_product` | `product_id` | that product never appears | e.g. the oversized sofa, the out-of-stock SKU |
| `bundle_within_budget_pct` | `max_pct` | every bundle is within budget×(1+max_pct/100) **or** flagged `exceedsBudget` | premium bundles may exceed if flagged |

> Unknown `type` = ignored (returns pass) so old reports never silently break;
> support it by adding a `case` to `_holds()`. Keep checks **objective** — taste
> belongs in `acceptance_criteria.human`, judged by an expert, never here.
