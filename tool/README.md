# `tool/` — Trust-Test harness (roadmap stage S0 → S1)

This is the cheapest possible evidence for the one question that matters most:
**does the deterministic engine produce furniture recommendations a real person
trusts?** (See `docs/cto_roadmap.md`.)

It runs the **real** engine — `domain_engine` + `shared/models`, which are pure
Dart — over realistic Saudi scenarios. **No Flutter, no device, no backend, no
AI.** The engine *is* the product, so we validate it before building anything
around it.

## Files
| File | What it is |
|---|---|
| `trust_test_scenarios.json` | 30 realistic + adversarial scenarios (input only) |
| `trust_test.dart` | headless runner over the real engine |
| `trust_test_report.md` | **generated** review packet (created on run) |

## Run it
From the repo root, on any machine with the Dart/Flutter SDK:

```bash
flutter pub get                 # one-time: resolves equatable + uuid
dart run tool/trust_test.dart   # prints the report and writes trust_test_report.md
```

> `dart run` compiles only the pure-Dart subtree this script imports, so it runs
> headless even though the wider project is a Flutter app. If you later split the
> engine into its own Flutter-free package, it will need only the Dart SDK.

## What the scenarios cover
- **Core happy paths:** bedroom / living room / majlis (guest room) / studio, across tight → generous budgets and modern / minimal / classic / mixed / unspecified styles.
- **Adversarial (the gold):** oversized sofa in a tiny room (spatial fit), budget below the essentials floor, an out-of-stock request, missing room dimensions, an unknown style, an unmatched color, Arabic synonym mapping (مكتب→طاولة, سجاد→سجادة), big budget vs small room, optional-only, and no-items fallback.

The adversarial cases matter most: they reveal whether the engine **degrades
sensibly** (flags, tradeoffs, "no good match") instead of returning nonsense.

## How to review (the V1 gate)
Put `trust_test_report.md` in front of **8–10 target users** and **≥1
furniture/interior expert**. For each scenario, compare the recommendations to
the stated human expectation and rate trust **1–5**:

| Score | Meaning |
|---|---|
| 1 | wrong / nonsensical |
| 2 | weak |
| 3 | acceptable |
| 4 | as I'd expect |
| 5 | as good as / better than I'd expect |

**V1 passes** when a clear majority land at **4–5** and no adversarial case
produces a confidently wrong answer. If it fails, the fixes are cheap — the
engine is pure Dart (weights, ceilings, filters). Once V1 passes, these
scenarios become the **golden regression set** — the engine's permanent
decision-quality suite and the real early Definition of Done.
