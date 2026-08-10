# Company Blueprint & Due-Diligence — the prompt

- **Status:** Prompt + applied (see `docs/org_blueprint.md`).
- **Purpose:** review the whole idea, then design the company as **departments →
  roles → headcount**, and hand an **acquirer** an honest "what exists / what's
  missing / what we do with what we have."
- **Use:** paste the prompt below; run it against this repo.

---

## THE PROMPT

> You are a **founder-operator + technical due-diligence lead**. Someone is
> evaluating buying **"التأثيث الذكي"** (an Arabic-first furniture *decision*
> app — thesis: *confidence is the product*, shopping is optional, AI is a tool).
> Produce a **Company Blueprint** they can act on. Be exact and honest; **do not
> inflate** — an acquirer punishes hand-waving.
>
> **Step 1 — Review the whole idea.** Read the repo and `docs/` (product thesis,
> CTO roadmap, catalog data strategy, AR, store-options ingestion, benchmark).
> In ≤10 lines summarize: the problem, the product, the moat, the business model,
> and the single biggest dependency.
>
> **Step 2 — Design the departments.** List every department the company needs to
> run. For **each**: its **mission** (1 line), **what it does** (3–6 concrete
> responsibilities), the **key outputs it owns**, and the **other departments it
> depends on**. Cover at least: Product, Engineering, Data, AI/ML, Design, 3D/AR
> Content, Partnerships/BD, Growth/Marketing, Ops-Finance-Legal, Customer/Trust —
> add or merge as the idea actually requires, and justify any change.
>
> **Step 3 — Staff each department.** Give headcount at **two stages** — **Lean
> (MVP/seed)** and **Scale** — and for **every role**: title, a one-line **mission**,
> **3–5 concrete duties**, the **artifact/metric they own**, and **seniority**.
> Totals per department and company-wide. No vanity roles — every seat must map
> to a real output.
>
> **Step 4 — The acquirer's view (exists / missing / leverage).** For each
> department, a 3-column table:
> - **EXISTS** — what is already built, citing the real repo artifact (file/dir).
> - **MISSING** — what an acquirer would expect but isn't there yet.
> - **WHAT WE DO WITH IT** — the plan to turn what exists into value + the first
>   hire/spend that unblocks it.
> Then a top-level **acquirer summary**: what you're buying, the 3 hardest gaps,
> the assets that de-risk it, and where the first riyal of capital should go.
>
> **Rules:** ground every "EXISTS" claim in an actual file/dir — no invented
> traction, users, revenue, or staff; if the honest answer is "one founder +
> AI-built prototype, zero employees, no real data/users/revenue," **say exactly
> that**. Tables over prose. Separate **the org you'd need** from **the reality
> today**. Currency SAR; region SA/GCC.
>
> **Deliver:** a single document with Steps 1–4, a department count, a per-stage
> headcount table, and a one-paragraph honest verdict a buyer could quote.
