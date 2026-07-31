# VP-1 (Product & Engineering) — "what I need to develop" prompt

*For the VP who owns Product & Strategy, Design (UX), Engineering, and AI/ML &
Evals. Paste the prompt below; run it against this repo. It returns a prioritized,
sequenced development plan grounded in what already exists — not a rebuild.*

---

## THE PROMPT

> You advise the **VP of Product & Engineering** at **التأثيث الذكي** (thesis:
> *confidence is the product; shopping is optional; AI is a tool*). This VP owns
> four departments: **Product & Strategy, Design (UX), Engineering, AI/ML & Evals**.
> The metric this VP owns is **activation = % of users who finalize a plan they
> trust**. Produce the concrete **things this VP must develop next**, ranked and
> sequenced, grounded in what already exists in the repo — **do not propose
> rebuilding what is already built.**
>
> **Step 1 — State of my domain.** Read the repo and `docs/org_blueprint.md`,
> `docs/product_thesis.md`, `docs/cto_roadmap.md`. For each of my four departments,
> one line: what's already built (cite the file/dir) and the single biggest gap.
> Known baseline you must respect as DONE: the **pure-Dart decision engine +
> confidence loop** (`lib/domain_engine/*`), the **deep options browser**
> (`lib/features/options`, `lib/features/plan`), **web AR + real-scale model**
> (`web/ar.html`, `tools/generate_furniture_glb.py`), and **CI/CD** to a live URL
> (`.github/workflows/flutter.yml`).
>
> **Step 2 — What to develop (prioritized table).** List the initiatives I must
> develop, ranked by impact on **activation/confidence**. For each row give:
> **what**, **why it moves confidence/activation**, **definition of done**,
> **which of my 4 departments owns it**, **dependencies** (including anything I
> need from VP-2's catalog contract), and a **size (S/M/L)**. Cover at least:
> 1. **Backend + accounts + plan sync** — wrap the existing `CatalogRepository`
>    with a real API; user accounts; save/restore/share a plan server-side.
>    *(Constraint: do not put Flutter or data-source concerns into the domain
>    engine — it stays pure.)*
> 2. **Instrument the confidence metric in production** — event pipeline that
>    measures activation, the confidence score distribution, and where users drop.
> 3. **Turn the Decision Benchmark into a CI quality gate** — grow real
>    expert-reviewed cases to volume; fail the build when a change regresses
>    decision quality (`benchmark/`).
> 4. **Natural-language input parsing** — free-text → `FurnishingProject` so a
>    user can just say "أبي سرير ودولاب بميزانية ٣٠٠٠" and get a seeded plan.
> 5. **App hardening** — accessibility (screen-reader Arabic), performance,
>    empty/error states, offline-first sync/conflict handling.
> 6. **Design system + Arabic-user research loop** — tokens/components pass and a
>    recurring test with real Arabic users feeding the confidence UI.
>
> **Step 3 — Sequence (90 days).** Order the above into milestones with an
> explicit **first two weeks** and **exit criteria** per milestone. Mark what can
> run in parallel across my departments.
>
> **Step 4 — My interface duties (boundary with VP-2 Supply & Growth).** State
> exactly what I must uphold: consume the **catalog/data contract**
> (`CatalogRepository`) without leaking data/sourcing concerns into the engine,
> and enforce the **confidence bar** every supplied product must pass (real
> dimensions for fit + AR, availability, price sanity).
>
> **Rules:** don't rebuild what exists; keep the domain engine Flutter-free; every
> item must tie to the confidence thesis or it's cut; be honest about effort and
> dependencies; prefer wrapping the existing interfaces over rewrites. **Output:**
> a prioritized table, a 90-day sequence, and the interface duties — no fluff.
