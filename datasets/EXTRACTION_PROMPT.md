# Furniture data-extraction prompt (per-product → catalog schema)

Give this prompt to an agent that has **authorized access** to a retailer's
product data — an **official feed, affiliate API, or a page it is permitted to
process** (see the legal note). It turns one product listing into a fully
structured catalog record with **every detail the Domain Engine needs to design
a room**.

> **Legal (non-negotiable, per `docs/catalog_data_sources.md`):** use **official
> APIs / affiliate feeds / licensed sources** only. Respect each site's
> robots.txt and Terms of Service. **No unauthorized scraping.** The chosen
> acquisition strategy is regional **affiliate feeds** (ArabClicks/Admitad →
> noon · Home Centre · HomeBox · Danube Home), enriched by GTIN.

## Target retailers (KSA / GCC first)
IKEA KSA · Home Centre (Landmark) · HomeBox · Danube Home · SACO · Homzmart ·
Pan Emirates · The One · Marina Home · noon (home). Extend later; keep the
`source` field so every record is traceable.

---

## The prompt

> You are a furniture data extractor. From the **authorized** product listing
> provided (feed row, API object, or permitted page), output **one JSON object**
> matching the schema below. Extract **only what is present** — never invent a
> value; use `null` for anything missing. Normalize: lengths → **cm**, price →
> **SAR**, digits → Western. Keep the original language for names/description.
>
> Capture, for the piece (e.g. a sofa): its **name**, **category** and
> subcategory, **every dimension** (width, depth, height — plus seat height /
> bed size / diameter when shown), **all colours**, **all materials**, **price**
> and currency, **availability**, **brand**, **all image URLs** (front + each
> side/angle shown), **rating**, which **rooms** it suits, a short
> **description**, **weight** if shown, and the **source** (retailer + exact
> URL). If the listing has variants (colour/size), emit **one record per
> variant** and share a `group_id`.
>
> Output strictly this JSON (no prose):

```json
{
  "product_id": "retailer_slug-or-sku",
  "group_id": "shared across variants of the same product | null",
  "source": { "retailer": "home_centre", "url": "https://…", "captured_at": "YYYY-MM-DD" },
  "title": "string (original language)",
  "category": "bed | sofa | rug | table | lamp | storage | other",
  "subcategory": "sectional | loveseat | queen_bed | …",
  "dimensions_cm": { "width": 190, "depth": 85, "height": 85, "seat_height": 45, "diameter": null },
  "color_tags": ["gray", "beige"],
  "material_tags": ["fabric", "wood"],
  "style_tags": ["modern"],
  "price": 990.0,
  "currency": "SAR",
  "availability_status": "in_stock | out_of_stock | preorder",
  "brand": "string | null",
  "rating_optional": 4.3,
  "room_suitability_tags": ["living_room", "guest_room"],
  "image_urls": ["https://…/front.jpg", "https://…/side.jpg"],
  "weight_kg": 32.0,
  "description": "string | null"
}
```

> Rules of quality: (1) if a required dimension is missing, set it `null` and add
> it to a `missing` array — **do not guess**; (2) map colours/materials/styles to
> a **controlled vocabulary** (extend the lists, don't free-text); (3) **dedup**
> by `group_id` or (brand + title + dimensions) or GTIN; (4) flag any price that
> looks impossible for the category for human review.

---

## Update cadence & versioning
- **Price + availability:** re-extract **daily** (they change often).
- **Full catalog:** re-extract **weekly**; publish an **immutable Curated
  Release vN** the decision engine pins (per `docs/catalog_strategy.md`).
- Every record carries `captured_at`; every release carries a version + source
  manifest so a stored Decision is reproducible.

## Mapping to the app
The app's `CatalogProduct` already holds the core facets (title, category,
`width/depth/height_cm`, colours, materials, price, brand, availability, rating,
`image_url`, `product_url`). The richer facets here (`image_urls[]`,
`seat_height`, `weight_kg`, `group_id`, per-source provenance) are the
**target model** from `docs/product_information_model.md`; extend
`CatalogProduct` toward this as real feeds land — additive, no rewrite.
