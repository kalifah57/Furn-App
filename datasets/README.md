# `datasets/` — furniture data acquisition

How the catalog gets **real, full-detail furniture data** (photos, all
dimensions, colour, material, price, availability) for the Domain Engine.

## Files
| File | What it is |
|---|---|
| `EXTRACTION_PROMPT.md` | the per-product extraction prompt (listing → full catalog record) |
| `sample_extraction_output.json` | an **illustrative** applied output showing the schema (not real data) |

## The honest picture (read this)
- **The data model is ready.** `CatalogProduct` already holds title, category,
  W/D/H, colours, materials, price, brand, availability, rating, image — and the
  extraction prompt targets the fuller model in `docs/product_information_model.md`.
- **Getting real data is a legal + access problem, not a coding one.** The
  chosen strategy (`docs/catalog_data_sources.md`) is **regional affiliate feeds
  / official APIs** — which return these fields for the top retailers (noon,
  Home Centre, HomeBox, Danube Home…). **Scraping the 10 companies directly is
  rejected** (ToS/legal risk) — it's not a shortcut, it's a liability.
- **This sandbox cannot reach live retailer sites** (network is proxy-limited),
  and I will **not fabricate** real prices/brands. So `sample_extraction_output.json`
  is clearly marked illustrative.

## To get real data (what actually unblocks it)
1. Get **affiliate-network access** (ArabClicks / Admitad) or an official
   retailer/API key — this is a business/account step, not code.
2. Run `EXTRACTION_PROMPT.md` over the authorized feed to produce records in the
   schema; validate each against the schema; dedup; enrich dimensions by GTIN.
3. Publish an immutable **Curated Release** the engine pins; refresh price/stock
   daily, full catalog weekly.
4. Load it via `RemoteCatalogRepository` behind the existing `CatalogRepository`
   interface — the app doesn't change.

Until then the app ships the bundled mock catalog (`assets/catalog/catalog.json`),
which already exercises the full decision loop.
