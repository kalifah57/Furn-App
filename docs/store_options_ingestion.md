# Store Options Ingestion — "give me real options from the stores"

- **Status:** Prompt + spec (ready to run the moment feed access exists)
- **Date:** 2026-07-31
- **Answers the ask:** "I set my budget and what I need, but you show me one generic pick. Where are the **options**? Give me options from IKEA, Home Centre, Home Box… deep results I can browse and try in AR."
- **Related:** `docs/catalog_data_sources.md` (the legal sourcing strategy), `datasets/EXTRACTION_PROMPT.md` (per-product extraction), `docs/ar_visualization.md` (the 3D/AR fields), `lib/shared/models/catalog_product.dart` (the schema the app reads).

> **What's already built (app side):** the app now shows **deep options per need** —
> tap "الخيارات (N)" on any plan item to compare every option with its **store,
> price, three dimensions + a "fits your room?" check, colours, materials, rating,
> and a "شاهدها في غرفتك" AR button.** It runs today on the bundled demo catalog.
> This doc is the pipeline that swaps that demo catalog for **real store options.**

---

## The honest constraint (read once)
Real IKEA / Home Centre / Home Box / noon / Danube options come from **authorized
affiliate feeds or official product APIs** — **not** scraping (rejected in
`catalog_data_sources.md` for ToS/legal reasons). Getting feed access is a
**business/account step**, not code. This sandbox can't reach live retailer sites
and must **never fabricate** real brands/prices. The moment you have an authorized
feed, the prompt below turns it into catalog records the app reads unchanged.

---

## INGESTION PROMPT (hand this to an agent with feed access)

> **Goal:** produce **N real, in-budget options per need** from authorized retailer
> feeds, in the exact `CatalogProduct` JSON schema this app loads, so the user can
> **browse, compare, and AR-preview** them.
>
> **Inputs:**
> - `needs`: the user's requested items (e.g. `["bed","wardrobe","lamp"]`) with
>   `essential` / `optional` priority.
> - `budget_max` (SAR), `room` (type + width×length in metres), `style`, `colors`.
> - `region`: SA / GCC. `min_options_per_need`: default **6**.
> - `authorized_sources`: the feeds you actually have (e.g. IKEA SA, Home Centre /
>   Landmark, Home Box, noon, Danube Home) via ArabClicks / Admitad / official API.
>
> **For each need**, pull at least `min_options_per_need` distinct products that
> match the category and are **priced at or under the share of budget** for that
> need, spanning a **range of prices** (budget → mid → premium) and **at least two
> retailers**. For each product emit one record:
> ```json
> {
>   "product_id": "<stable id, e.g. retailer:sku>",
>   "title": "<Arabic title>",
>   "category": "bed|sofa|wardrobe|table|lamp|rug|chair|storage|...",
>   "subcategory": "<e.g. queen_bed>",
>   "style_tags": ["modern"], "color_tags": ["gray"], "material_tags": ["wood","fabric"],
>   "width_cm": 0, "depth_cm": 0, "height_cm": 0,
>   "price": 0.0, "currency": "SAR",
>   "brand": "<real brand>", "supplier": "<retailer>",
>   "availability_status": "in_stock|out_of_stock",
>   "rating_optional": 4.3,
>   "room_suitability_tags": ["bedroom"],
>   "image_url": "<official image URL from the feed>",
>   "product_url": "<affiliate/product URL — the 'في المتجر' link>",
>   "model_glb_url": "<GLB if the feed provides 3D, else \"\">",
>   "model_usdz_url": "<USDZ if provided, else \"\">",
>   "ar_ready": false
> }
> ```
>
> **Rules:**
> 1. **Only authorized feeds.** No scraping, no invented prices/brands/URLs. If a
>    field isn't in the feed, leave it empty/`null` — never guess.
> 2. **Real dimensions are mandatory** (`width/depth/height_cm`) — they drive the
>    "fits your room?" check and real-scale AR. Enrich by GTIN where missing.
> 3. **Diversity per need:** span price tiers and ≥2 retailers so the options list
>    is a genuine comparison, not near-duplicates.
> 4. **AR:** set `ar_ready:true` **only** when both `model_glb_url` and
>    `model_usdz_url` exist and are verified at real scale (see
>    `docs/ar_visualization.md` §7). Otherwise `ar_ready:false` and the app simply
>    hides the AR button for that product — everything else still works.
> 5. **Validate** every record against `CatalogProduct.fromJson` (types, category
>    enum, non-negative dimensions/price); drop or fix invalid rows; dedup by
>    `product_id` and by (title+brand+dimensions).
> 6. **Availability & price** are the volatile fields — mark records with a
>    `captured_at` so a daily refresh can update price/stock without a full re-pull.
>
> **Deliver:** a single `products` JSON array (schema above), a short validation
> report (counts per need, per retailer, price range, % with dimensions, % AR-ready),
> and the list of any needs that couldn't reach `min_options_per_need` so sourcing
> can be widened. Load it via `RemoteCatalogRepository` behind the existing
> `CatalogRepository` interface — **the app UI does not change.**

---

## How this lands in the app (no rework)
1. The record schema above **is** `CatalogProduct` (incl. the AR fields added in
   `catalog_product.dart`). Drop the JSON in and the deep-options browser, the
   "fits your room?" check, the store link, and the AR button all light up.
2. Ship it as an **immutable Curated Release** the engine pins; refresh price/stock
   daily, full catalog weekly (`catalog_data_sources.md`).
3. `product_url` becomes the **"في المتجر"** link; `image_url` fills the option
   cards; `model_*_url`+`ar_ready` enable per-product "شاهدها في غرفتك".

## What unblocks real data (the business step)
1. Get **affiliate-network access** (ArabClicks / Admitad) or an official retailer
   API key for the target stores.
2. Run this prompt over the authorized feed → validated `products` array.
3. Publish the Curated Release; the app serves real options immediately.

Until then the app ships the bundled demo catalog (`assets/catalog/catalog.json`),
which already exercises the full **browse → compare → AR → choose** loop.
