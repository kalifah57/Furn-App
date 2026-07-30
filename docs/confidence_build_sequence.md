# Confidence build sequence — 10 serial prompts (answer → apply → run)

- **Date:** 2026-07-30
- **Purpose:** Turn "confidence is the product" into a buildable order. Each step is a pair — **Answer** (the confidence mechanic) + **Apply** (a runnable prompt that puts it in the app). Feed the Apply prompt to an agent (or a future session **with Flutter**) to execute it.
- **What's already executed this session:** the loop's **pure-Dart core** — `lib/domain_engine/plan/plan.dart` + `plan_workspace.dart` + `test/domain_engine/plan_workspace_test.dart`. That covers the **logic** of steps 1–5, 7, 8, and most of 9–10. What remains is **Flutter UI wiring**, which needs a runtime this environment doesn't have. Status is marked per step.

> Honest note: no Flutter/Dart SDK here, so the core is written and structurally validated but **not run**. "Apply" prompts that touch UI need a local `flutter run`; the confidence *is* in the loop's logic, which is built and reviewable now.

---

## 1 — The Plan is the center
**Answer:** People trust an artifact they *own and shape*, not a feed. Make the plan the home screen.
**Apply:** "Add a `PlanController` (Riverpod `Notifier`) holding a `PlanWorkspace`; make `PlanScreen` the app's home, watching `workspace.build()` and rendering the plan (items, total)."
**Status:** ✅ core (`Plan`, `PlanWorkspace`) · ⏳ `PlanScreen` + controller.

## 2 — Pin (lock what I love)
**Answer:** Agency is the #1 confidence source — you trust what you authored.
**Apply:** "On each plan item add a ❤️ pin toggle → `controller.pin(id)` / `unpin(id)`, then rebuild. Pinned items render locked and are never replaced."
**Status:** ✅ `pin/unpin` + pins own their category · ⏳ the toggle UI.

## 3 — Reject (never show this)
**Answer:** Removing the unwanted is as reassuring as adding the wanted — it proves the tool obeys you.
**Apply:** "Add a ✕ reject action → `controller.reject(id)`; the plan re-balances without it."
**Status:** ✅ `reject` + excluded from re-seed · ⏳ the action UI.

## 4 — Swap (see alternatives, choose)
**Answer:** Seeing the alternatives you *considered* kills "maybe something better exists."
**Apply:** "Add 'see alternatives' per item → `workspace.alternativesFor(category)`; picking one calls `swap(out,in)`. Show each alternative's ±price vs the current pick."
**Status:** ✅ `alternativesFor` + `swap` · ⏳ the alternatives sheet.

## 5 — Budget slider → re-balance
**Answer:** Watching the plan respond to *your* number builds ownership and removes budget dread.
**Apply:** "Add a budget slider → `controller.setBudget(v)` on change; rebuild live so total + assurances update instantly (<100ms)."
**Status:** ✅ `setBudget` + re-seed · ⏳ the slider + instant rebuild.

## 6 — Plain-language "why" (item + change)
**Answer:** You trust what you understand; a black box breeds doubt.
**Apply:** "Show `item.reason` under every item. After each edit, show a one-line change note built from `PlanWorkspace.diff(before, after)` (e.g. 'freed 260 SAR, dropped the pricier bed')."
**Status:** ✅ reasons + `diff` data · ⏳ the "what changed" line.

## 7 — Assurance badges (✓ fits · ✓ budget · ✓ available · ✓ complete)
**Answer:** "This won't embarrass me or overspend" — the guarantee that all the invariant work becomes a *felt* feature.
**Apply:** "Render `plan.assurances` as a badge row; each ✓/⚠ is tappable to explain itself."
**Status:** ✅ `Assurances` derived · ⏳ the badge row.

## 8 — Completeness checklist (nothing forgotten)
**Answer:** Furnishing anxiety is mostly "what am I missing?"
**Apply:** "If `plan.missingCategories` is non-empty, show a gentle 'still to add: …' prompt with one-tap add."
**Status:** ✅ `missingCategories` · ⏳ the checklist strip.

## 9 — Compare versions + revert
**Answer:** People explore boldly only when they can't break anything — and bold exploration forms conviction.
**Apply:** "Snapshot `Plan` on each finalize/save; add a Compare view using `PlanWorkspace.diff`; allow revert to a snapshot."
**Status:** ✅ `diff` · ⏳ snapshot history + compare/revert UI.

## 10 — Confidence signal + Finalize + share
**Answer:** A real (never fake) signal that rises with true progress, then a moment of arrival — and family buy-in turns social risk into social proof.
**Apply:** "Show `plan.confidence` as an honest ring (breakdown on tap). Add a Finalize action → `controller.finalizePlan()` reaching a 'This is your plan — you've got this' screen with share (read-only) + export checklist."
**Status:** ✅ `confidence` + `finalizePlan` · ⏳ the ring, finalize screen, share/export.

---

## The build order in one line
Plan-as-home (1) → make it obey you (2,3,4,5) → make it explain itself (6,7,8) → make it safe to explore and finish (9,10). Ship 1–8 in the 6-week MVP; 9–10 close the loop. Everything else in the old roadmap waits.
