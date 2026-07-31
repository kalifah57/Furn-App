# التأثيث الذكي — Company Blueprint & Due-Diligence (applied)

*Applied from `docs/org_blueprint_prompt.md`. Honest by design: separates **the
org you'd need** from **the reality today**. Currency SAR; region SA/GCC.*

---

## Step 1 — The idea, in ten lines
- **Problem:** furnishing a room is high-stakes and low-confidence — too many options, unclear fit/budget, fear of a wrong buy.
- **Product:** an Arabic-first, RTL app that turns *room + budget + needs* into a **Plan you trust** — pin/reject/swap/adjust until a transparent **confidence score** is high. *Confidence is the product; shopping is optional; AI is a tool.*
- **Moat:** a deterministic **decision engine + confidence loop** and a permanent **Decision Benchmark** (evals) — not another storefront.
- **Business model:** affiliate commission on referred purchases (+ future retailer placements / SaaS for stores).
- **Biggest dependency:** **authorized retailer/affiliate data** (real options, prices, dimensions, 3D) — a commercial/legal deal, *not* code.

## Step 2 — Departments (9)

| # | Department | Mission | What it does (owns) |
|---|---|---|---|
| 1 | **Product & Strategy** | Keep "confidence is the product" true | Roadmap, prioritization, the confidence-metric definition, requirements |
| 2 | **Engineering** | Ship the app + engine + platform | Flutter app, pure-Dart decision engine, backend/API, AR, CI/CD |
| 3 | **Data & Catalog** | Turn feeds into a trustworthy catalog | Affiliate/API ingestion, dimension/GTIN enrichment, curated releases, price/stock refresh |
| 4 | **AI/ML & Evals** | Make the recommendation *provably* good | Ranking quality, NL input parsing, and the Decision Benchmark + rubric |
| 5 | **Design (UX + Visual)** | Make trust legible | RTL Arabic UX, the confidence/plan/options flows, brand, research |
| 6 | **3D / AR Content Ops** | "See it in your room," at real scale | Per-SKU GLB/USDZ pipeline, scale validation, asset library |
| 7 | **Partnerships & BD** | Unlock real data + supply | Retailer/affiliate deals (IKEA, Home Centre, HomeBox, noon, Danube), network access (ArabClicks/Admitad) |
| 8 | **Growth & Marketing** | Bring Arabic users cheaply | Acquisition, ASO, content, funnel to "confidence," lifecycle |
| 9 | **Ops, Finance & Legal (+ Customer/Trust)** | Keep it legal, funded, trusted | Unit economics, ToS/affiliate/privacy compliance, support, trust feedback loop |

**Dependency spine:** BD (7) unlocks Data (3) → feeds Engine/AI (4) + AR (6) → surfaced by Eng (2)/Design (5) → distributed by Growth (8) → governed by Ops (9), all steered by Product (1).

## Step 3 — Staffing (Lean vs Scale)

| Department | Lean (MVP/seed) | Scale | Key roles & what each person does |
|---|---:|---:|---|
| Product & Strategy | 1 | 4 | **CPO/Head of Product** — owns thesis, roadmap, confidence metric. *(Scale: Sr PM Decision-Loop, PM Catalog/Options, Product Analyst — funnel + A/B)* |
| Engineering | 4 | 14 | **Eng Lead/CTO** — architecture, ADRs, delivery • **Flutter Eng** (1→4) — app/RTL, plan+options screens • **Core/Domain Eng** (1→2) — the pure-Dart engine + invariants • **Backend/Platform Eng** (1→3) — catalog API, auth, sync, storage • **AR/3D Eng** (½→1) — model-viewer AR + 3D integration • **DevOps** (½→1) — CI/CD, hosting • **QA/Test** (½→2) — benchmark harness + coverage |
| Data & Catalog | 1 | 5 | **Data Lead** — sourcing strategy, curated releases • **Pipeline Eng** (→2) — feed ingestion, GTIN/dimension enrichment • **Data Quality/Ops** (→1) — validation, dedup, price/stock refresh • **Catalog Merch** (→1) — coverage/curation |
| AI/ML & Evals | 1 | 3 | **Applied ML Eng** — ranking, NL→project parsing, explanations • **Evals/Benchmark owner** — Decision Benchmark, expert rubric, scoring • *(Scale: Data Scientist — confidence calibration)* |
| Design | 1 | 4 | **Product Designer (UX)** — RTL trust UX, plan/options flows • *(Scale: Sr UX, Visual/Brand, Arabic UX Researcher)* |
| 3D / AR Content Ops | 0\* | 4 | *(Lean: outsourced/generated)* → **3D Lead + Artists/Scan Ops** — per-SKU GLB/USDZ at real scale, scale QA |
| Partnerships & BD | 1 | 4 | **BD Lead** — retailer/affiliate deals + network access (the unlock) • *(Scale: Partnerships Mgrs ×2, Affiliate Ops ×1)* |
| Growth & Marketing | 1 | 5 | **Growth Lead** — acquisition, ASO, funnel • *(Scale: Performance, Content/Social Arabic ×2, Lifecycle/CRM)* |
| Ops, Finance & Legal (+ Trust) | 1 | 3 | **COO/Ops** (often founder-CEO) — finance, hiring, ToS/affiliate/privacy, unit economics • **Customer/Trust & Support** (shared→1-2) — support + feedback into the confidence metric • *(Scale: fractional Finance/Legal)* |
| **Total** | **≈ 11** | **≈ 46** | \*3D is outsourced/AI-generated at Lean stage |

## Step 4 — The acquirer's view: EXISTS / MISSING / LEVERAGE

| Department | ✅ EXISTS (in repo) | ❌ MISSING | ➜ WHAT WE DO WITH IT (first unblock) |
|---|---|---|---|
| Product | Thesis + roadmaps: `docs/product_thesis.md`, `docs/cto_roadmap.md`, `docs/confidence_build_sequence.md` | Live funnel data, a measured confidence metric | Prototype validates the thesis cheaply; instrument the confidence metric once there are users |
| Engineering | Working app (`lib/features/*`), **pure-Dart decision engine + confidence loop** (`lib/domain_engine/*`), deep **options browser** (`lib/features/options`), **CI/CD** → live URL (`.github/workflows/flutter.yml`) | **Backend/API, auth, accounts, sync** (all client-side/mock today) | Tech risk is largely retired; first backend hire wraps the existing `CatalogRepository` with a real API — UI unchanged |
| Data & Catalog | Strategy + prompts: `docs/catalog_data_sources.md`, `datasets/EXTRACTION_PROMPT.md`, `docs/store_options_ingestion.md`; 48-item **mock** catalog | **Real retailer data** (prices, stock, dimensions) | The moment BD lands one feed, the ingestion prompt fills the *same* schema → real options overnight |
| AI/ML & Evals | Deterministic recommender + **Decision Benchmark scaffold** (`benchmark/`, invariants + rubric) | Trained ranking, real expert-reviewed cases at volume, NL input parsing | Evals scaffold makes quality *measurable* now; grow cases, then optimize ranking against them |
| Design | RTL Arabic-first UI live; confidence ring, assurances, plan/options, AR entry | Research with real Arabic users; brand system | UX is real and testable; validate with users, then systematize brand |
| 3D / AR Content Ops | **Working web AR** (`web/ar.html`), **real-scale generator** (`tools/generate_furniture_glb.py`) + a live model (`web/models/*.glb`) + `docs/ar_visualization.md`, `docs/furniture_to_ar.md` | Per-SKU real 3D assets (scan/model each product) | Pipeline + wiring done; capex/ops to build the asset library per priority SKU |
| Partnerships & BD | The strategy + the exact data the deals must return | **The deals themselves** (no signed feed/affiliate access) | **This is the master unlock** — one retailer/affiliate deal converts the whole prototype into a real product |
| Growth & Marketing | Arabic-first positioning; a shareable live URL | Users, channels, CAC/LTV, ASO | Zero-to-one distribution; start after real data makes the app worth sharing |
| Ops, Finance & Legal | ToS-safe data stance (no scraping) baked into strategy | Entity, unit economics, privacy/affiliate compliance, support | Compliance posture chosen early (de-risks legal); stand up entity + economics at seed |

### Acquirer summary (quote-ready)
> **What you're buying:** a **working, offline-first Arabic furniture-*decision*
> prototype** — a clean pure-Dart decision engine + confidence loop, a deep
> options-browser UX, a **real-scale AR pipeline with a live generated model**,
> an **evals scaffold** (Decision Benchmark), and a documented data/AR/BD
> strategy — all built by **one founder with an AI agent** and continuously
> deployed to a live URL.
>
> **What you're NOT buying (be clear):** any real retailer data, per-SKU 3D
> assets at scale, a backend, users, revenue, or a staffed team. These are
> **specified and wired, not yet realized**.
>
> **Three hardest gaps:** (1) **authorized retailer/affiliate data** — a BD/legal
> deal, not code; (2) **per-SKU 3D assets** — 3D ops/capex; (3) **distribution/
> users** — growth from zero.
>
> **What de-risks it:** the architecture, engine, evals, and strategy collapse
> most *product/tech* risk, so the remaining risks are **commercial** (deals,
> capex, CAC) rather than technical — a cleaner bet than a typical pre-seed idea.
>
> **First riyal of capital → Partnerships/BD** to land one retailer feed; that
> single deal turns the entire prototype into a real, priced, in-stock catalog —
> and everything else (AR, options, confidence) already knows what to do with it.
