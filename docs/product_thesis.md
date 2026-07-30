# Product thesis — Furn (founder's rewrite)

- **Status:** Founding product definition — supersedes the "app/engine" framing for product decisions
- **Date:** 2026-07-30

> **Confidence is the product.** The recommendation is only the seed. The plan you trust is the deliverable. Shopping is optional. AI is a hidden tool.

## The business we're really in
Not furniture. Not AI. The **confidence business** — we sell *certainty about a high-stakes, emotional home decision*. Neighbors: financial planning, wedding planning. Furniture is the domain; confidence is the commodity.

## The transformation we sell
From **"overwhelmed, second-guessing, scared of an expensive mistake"** → **"This is my plan. I've got this."**

## One-liners
- **Product:** a workspace that turns furnishing anxiety into a plan you trust.
- **Value:** stop second-guessing your home — reach a furnishing plan you're genuinely confident in, before you spend a riyal.
- **UX:** describe your space and budget → get one honest starting plan → reshape it (swap, pin, reject, slide the budget, compare) while it re-balances and explains itself → until you feel sure → lock it.

## The center: the PLAN
The app revolves around **the Plan** — a living, ownable, editable artifact — not a recommendation, a store, or a feed. Recommendation = seed. Plan = product. (Chosen over "Decision" because confidence is *built iteratively* — you refine a plan; you don't refine a moment.)

## The confidence loop (the actual product)
first plan → swap · add · remove · **pin** what you love · **reject** what you don't · slide the budget · change style → system **re-balances** and shows total, fit, trade-offs, and **why** → compare versions → confidence signal rises → **Finalize ("this is the one")** → keep · **share for family buy-in** · export checklist.

Principle: **the user expresses intent; the system owns the consequences.** Editing must feel like shaping clay, not filling a form. `pin` / `reject` are the core primitives — they let the user steer without starting over.

## North Star
**Trusted Plans finalized** — a user reaches a plan they explicitly lock as "this is the one," with a one-tap confidence check at that moment. Not downloads, not AI calls, not recommendations generated. It is the transformation, measured.

## Full value without buying
**Yes.** The "aha" — *I know what I want and I'm sure* — happens entirely before purchase. If they leave with a trusted plan, they received the whole product, even if they buy elsewhere, later, or never.

## 6-week MVP (one dev)
The confidence loop on **mock data**. Nothing else. No backend, real AI, real catalog, spatial/3D, shopping, or multi-room. Reuse the existing engine **only** as the seed generator.

## Cut from the roadmap (≈70%)
backend/sync · real AI · catalog ingestion · spatial/Measurement · semantic search · shopping/checkout · multi-room · CI. Keep only: the plan workspace + the edit/compare/refine loop + the confidence signal + save/share.

## Biggest misconception
That the recommendation's **quality** is the product. A mediocre plan the user **shaped himself** builds more confidence than a perfect one he can't touch. Optimize for **authorship and control**, not oracle accuracy. (Corollary: AI is the least important part.)

## The two things that kill us even with perfect software
1. **Furnishing is a one-off, not a habit.** Deliver confidence and the user is *done* — no return, no repeat, no referral. Without a **share / family-approval loop** and **room-by-room-over-time** re-engagement, we build a tool used once, with no distribution.
2. **Confidence-first vs. how we earn.** If shopping is optional, affiliate revenue thins. Monetization must come from the trust we build — high-intent, plan-ready buyers retailers pay for; premium compare/share; not from forcing a checkout that betrays the promise.

## What we are NOT
a store · a marketplace · a catalog · an AI gimmick · a recommendation engine. We are where you go to **stop second-guessing your home.**
