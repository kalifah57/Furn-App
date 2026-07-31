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

## Architecture (mirrors the repo's repository seam)
- `lib/analytics/analytics.dart` — `Analytics` interface + a **sealed** `AnalyticsEvent`
  set (typed props, no free-form maps).
- Sinks: **`NoopAnalytics`** (default — drops everything), **`DebugAnalytics`**
  (records + logs; used by tests and the live web console), **`RemoteAnalytics`**
  (stub — same interface, no network yet).
- `analyticsProvider` (Riverpod, default `Noop`); `main.dart` overrides it to
  `DebugAnalytics` so events are observable. Production swaps to `RemoteAnalytics`
  via that one line — no call-site changes.
- **Privacy:** anonymous per-session id only (ties to the anonymous `AppUser`), no
  PII, and a `consent` flag (PDPL) that hard-drops all events when false.

## Event catalog
| Event | Fires when | Props |
|---|---|---|
| `flow_started` | user enters the journey (onboarding / plan demo) | `source` |
| `input_submitted` | a project is formed from any input | `roomType, hasBudget, essentialCount, optionalCount, inputMode` (manual\|text\|voice\|image) |
| `plan_seeded` | the plan is first built | `confidence, itemCount, missingCount, total, withinBudget` |
| `item_pinned` / `item_rejected` / `item_swapped` | user shapes the plan | `category` |
| `budget_changed` | user moves the budget slider | `newMax, deltaConfidence` |
| `options_opened` | user opens the options browser for a need | `category, optionCount` |
| `ar_opened` | user launches "see it in your room" | `target` (productId \| `demo`) |
| `plan_finalized` | user commits to the plan (activation) | `confidence, itemCount, pinnedCount, edits` |
| `plan_shared` | user opens the share sheet | `confidence` |
| `session_abandoned` | user leaves the plan without finalizing (once) | `lastStep, lastConfidence` |

## Wire points (real files)
`flow_controller.dart` (`input_submitted`), `plan_controller.dart` (`plan_seeded`,
pin/reject/swap, `budget_changed`, `plan_finalized`, `options_opened` via
`logOptionsOpened`, `plan_shared` via `logShared`, `session_abandoned` via
`logAbandonedIfUnfinished`), `plan_screen.dart` (calls the log helpers +
`dispose` → abandoned), `onboarding_screen.dart` (`flow_started`),
`features/ar/ar_button.dart` (`ar_opened`).

## Extending
Add a `final class` to the `AnalyticsEvent` sealed set with a stable snake_case
`name` and typed `params`, then `track(...)` it at the controller/screen layer —
never inside `lib/domain_engine/`.
