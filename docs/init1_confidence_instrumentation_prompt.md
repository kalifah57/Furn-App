# Initiative #1 — Instrument the confidence / activation metric (prompt)

*The VP-1 top priority: measure activation before optimizing it. Self-contained,
in-repo, no external service to start. Paste the prompt below and run it.*

---

## THE PROMPT

> **Role & goal.** You are a senior Flutter/Dart engineer on **التأثيث الذكي**
> (thesis: *confidence is the product*). Build **production instrumentation for the
> confidence loop** so we can measure **activation = % of sessions that finalize a
> plan the user trusts**, the **confidence-score distribution at finalize**, and the
> **drop-off** between steps. **Do not touch the pure-Dart domain engine**
> (`lib/domain_engine/*` stays Flutter-free *and* analytics-free) and **do not
> rebuild** the confidence loop — only observe it.
>
> **Architecture — mirror the repo's existing seam pattern** (`CatalogRepository`,
> `AuthRepository`, `ProjectRepository` = interface + mock/in-memory + Riverpod
> provider). Add:
> - `lib/analytics/analytics.dart` — `abstract interface class Analytics { void track(AnalyticsEvent e); }`
> - `AnalyticsEvent` — a **sealed/typed** set (name + typed props); no free-form maps.
> - `DebugAnalytics` (collects/prints, for dev + tests), `NoopAnalytics` (default),
>   and a `RemoteAnalytics` **stub** behind the same interface (no real network yet).
> - `analyticsProvider` (Riverpod), overridable in tests.
>
> **Events to emit (the confidence funnel)** — at the controller/screen layer,
> **never** in the engine:
>
> | Event | Where (real file) | Key props |
> |---|---|---|
> | `flow_started` | onboarding / plan entry | source (onboarding \| plan-demo) |
> | `input_submitted` | `room_input/.../flow_controller.dart` | roomType, hasBudget, essentialCount, optionalCount, inputMode (manual\|voice\|image) |
> | `plan_seeded` | `plan/.../plan_controller.dart` (first build) | confidence, itemCount, missingCount, total, withinBudget |
> | `item_pinned` / `item_rejected` / `item_swapped` | `plan_controller.dart` | category |
> | `budget_changed` | `plan_controller.dart` setBudget | newMax, deltaConfidence |
> | `options_opened` | `plan_screen.dart` options sheet | category, optionCount |
> | `ar_opened` | `features/ar` buttons | productId \| "demo" |
> | `plan_finalized` | `plan_controller.dart` finalizePlan | **confidence**, itemCount, pinnedCount, edits (# pin/reject/swap before finalize) |
> | `plan_shared` | share dialog | confidence |
> | `session_abandoned` | app lifecycle detach w/o finalize | lastStep, lastConfidence |
>
> **The metric.** Define **activation = plan_finalized / flow_started** (per
> session); also **median confidence at finalize** and the **funnel** started →
> seeded → engaged (≥1 edit) → finalized. Emit a per-session **anonymous** id
> (reuse the existing anonymous `AppUser` from `MockAuthRepository`); **no PII**,
> PDPL/Arabic-market aware; include a **consent/kill-switch** flag.
>
> **Wire points (real files).** `lib/features/plan/presentation/plan_controller.dart`
> (pin/unpin/reject/swap/setBudget/finalizePlan), `lib/features/room_input/
> presentation/flow_controller.dart` (started/submitted/recommend),
> `lib/features/plan/presentation/plan_screen.dart` (options/AR/share), onboarding
> entry. Inject `Analytics` via provider; keep every call-site a one-liner.
>
> **Rules.** The engine stays pure — add a **test that greps `lib/domain_engine/`
> for any `analytics` import and fails if found**. Typed events only. Default sink
> is `Noop` until a real sink is chosen. Everything behind DI so tests override it.
>
> **Definition of Done.** (1) events fire through a swappable sink; (2) a
> unit/widget test drives `DebugAnalytics` and asserts the funnel for one **happy
> path** (start → seed → pin → finalize with confidence) and one **abandon path**;
> (3) `docs/analytics_events.md` — the event catalog + the activation/funnel
> definitions; (4) `flutter analyze` + `flutter test` green in CI.
>
> **Deliver:** the `lib/analytics/` module, the wiring at the call-sites, the test,
> and the event-catalog doc. Nothing in the domain engine changes.
