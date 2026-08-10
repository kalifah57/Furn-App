# Analytics — the confidence funnel (event catalog)

*Initiative #1 applied. Instrumentation only — it **observes** the confidence loop
and never changes it. The pure-Dart domain engine stays analytics-free (enforced by
`test/analytics/engine_purity_test.dart`).*

## The metric
- **Activation = `plan_finalized` / `flow_started`** per session — the share of
  users who reach a plan they trust enough to finalize.
- **Median confidence at finalize** — from `plan_finalized.confidence` (0–100).
- **Funnel:** `flow_started` → `plan_seeded` → **engaged** (≥1 of pin/reject/swap/
  budget) → `plan_finalized`. Each step's drop-off is `1 − next/prev`.
- **Returning sessions are not seeds.** Since plans persist, a session that
  restores a saved plan emits `plan_restored` and **no** `plan_seeded`. Counting a
  page refresh as a new seed would inflate the funnel's numerator — the one number
  we judge the product by. So a session with edits but no `plan_seeded` is not a
  gap in the data; look for `plan_restored`. `plan_restored / (plan_seeded +
  plan_restored)` is its own signal: how many people come back to their plan.

## Architecture (mirrors the repo's repository seam)
- `lib/analytics/analytics.dart` — `Analytics` interface + a **sealed** `AnalyticsEvent`
  set (typed props, no free-form maps).
- Sinks: **`NoopAnalytics`** (drops everything), **`DebugAnalytics`** (records +
  logs; used by tests and the live web console), **`HttpAnalytics`** (batches and
  POSTs to an endpoint), **`FanOutAnalytics`** (feeds several sinks at once).
- `analyticsProvider` composes them, and **the whole decision lives there** — not
  in `main.dart`, which used to override the provider and would have silently
  discarded the real sink. Debug in `kDebugMode`, plus HTTP when
  `--dart-define=ANALYTICS_ENDPOINT=…` is set. **No endpoint ⇒ nothing is sent:**
  shipping user data to a destination nobody chose is not a default.
- **Privacy:** anonymous per-session id only (ties to the anonymous `AppUser`), no
  PII, and a `consent` flag (PDPL) that hard-drops all events when false.

## Event catalog
| Event | Fires when | Props |
|---|---|---|
| `flow_started` | user enters the journey | `source` (`onboarding` \| `sample_plan`) |
| `input_submitted` | a project is formed from any input | `roomType, hasBudget, essentialCount, optionalCount, inputMode` (manual\|text\|voice\|image) |
| `plan_seeded` | the plan is built for the first time | `confidence, itemCount, missingCount, total, withinBudget` |
| `plan_restored` | a saved plan is loaded back (refresh, or a later visit) — **replaces** `plan_seeded` for that session | `confidence, itemCount, decisions` |
| `item_pinned` / `item_rejected` / `item_swapped` | user shapes the plan | `category` |
| `budget_changed` | user moves the budget slider | `newMax, deltaConfidence` |
| `options_opened` | user opens the options browser for a need | `category, optionCount` |
| `ar_opened` | user launches "see it in your room" | `target` (productId \| `demo`) |
| `plan_finalized` | user commits to the plan (activation) | `confidence, itemCount, pinnedCount, edits` |
| `plan_shared` | user opens the share sheet | `confidence` |
| `need_unmet` | user asked for something we cannot serve | `raw_type` (their words), `reason` (`out_of_scope`\|`not_stocked`\|`none_fit`), `reserve_sar` |
| `session_abandoned` | user leaves the plan without finalizing (once) | `lastStep, lastConfidence` |

## Wire points (real files)
`flow_controller.dart` (`input_submitted`), `plan_controller.dart` (`plan_seeded`
or `plan_restored` — exactly one, on construction; then
pin/reject/swap, `budget_changed`, `plan_finalized`, `options_opened` via
`logOptionsOpened`, `plan_shared` via `logShared`, `session_abandoned` via
`logAbandonedIfUnfinished`), `plan_screen.dart` (calls the log helpers +
`dispose` → abandoned), `onboarding_screen.dart` (`flow_started`),
`features/ar/ar_button.dart` (`ar_opened`).

## Extending
Add a `final class` to the `AnalyticsEvent` sealed set with a stable snake_case
`name` and typed `params`, then `track(...)` it at the controller/screen layer —
never inside `lib/domain_engine/`.
