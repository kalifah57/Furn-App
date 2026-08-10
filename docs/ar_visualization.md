# AR — "see it in your room" (research + implementation prompt)

> **خارج نطاق الـ MVP (2026-08).** التطبيق ويب، والتجارب ثلاث (ADR-0002)؛ شاشة
> الواقع المعزّز ومنظومة المسح حُذفت من الشيفرة بعد فرز الوصول. يبقى فقط زرّ
> «شاهدها في غرفتك» (نافذة `<model-viewer>` في المتصفّح). هذه الوثيقة مرجع بحثي
> للمستقبل، لا وصفٌ لما هو مبنيّ.

- **Status:** Research + design (out of MVP scope; screen removed)
- **Date:** 2026-07-30
- **Scope:** Augmented Reality "try this furniture in your actual room" — the tech, the chosen approach for *this* app, the hard dependency (3D models), and a self-contained prompt you can hand to an agent to build it.
- **Related:** `docs/vision_architecture.md`, `docs/catalog_data_sources.md`, `docs/product_information_model.md`, `datasets/EXTRACTION_PROMPT.md`

> The feature: open the camera, see the real sofa/bed placed on your floor at **true size, colour, and detail**, walk around it, then decide. IKEA Place is the benchmark.

---

## 1) How furniture AR actually works
Plane detection finds the floor; you tap to place the model; drag / pinch / two-finger-rotate to position it; ambient-light estimation + a contact shadow make it look real. Two engines do the heavy lifting: **ARKit** (iOS) and **ARCore** (Android). Every approach needs **3D models** — **GLB/glTF** (Android/web) and **USDZ** (iOS/Quick Look), typically **< 5 MB** each, authored at **real-world scale**. [zigpoll guide](https://www.zigpoll.com/content/how-can-i-integrate-an-augmented-reality-feature-in-my-app-to-help-customers-visualize-furniture-in-their-homes-before-making-a-purchase) · [360render GLTF vs USDZ](https://www.360render.com/rendering-guide/gltf-vs-usdz-the-best-3d-model-formats-for-e-commerce-ar-and-vr/)

## 2) Two paths — and the right one for us
| Path | What | Fit for us |
|---|---|---|
| **Native ARKit/ARCore** (Flutter `ar_flutter_plugin` etc.) | full in-app AR, occlusion, multi-item layout | ✗ heavy; our app runs as **Flutter web**, which can't reach ARKit/ARCore directly |
| **Web AR via `<model-viewer>`** | one HTML component → **AR button** that launches **Quick Look** (iOS Safari, USDZ) or **Scene Viewer / WebXR** (Android, GLB) — **no app install** | ✓✓ matches our web-on-mobile reality exactly |

**Chosen: `<model-viewer>` web AR.** A single component gives an interactive 3D
view + real-size AR placement on both iOS and Android, straight from the browser
the user already has open. [Google model-viewer AR](https://developers.google.com/ar/develop/webxr/model-viewer) · [Scene Viewer](https://developers.google.com/ar/develop/scene-viewer) · [Khronos: glTF in AR on Android](https://www.khronos.org/blog/view-a-gltf-model-in-ar-on-android-without-leaving-your-browser)

## 3) The hard dependency (be honest about it)
AR is **not a code problem, it's a 3D-asset problem.** Every catalog product needs
a **GLB + USDZ** at real-world scale with correct colour/material. Sourcing:
1. **Supplier-provided 3D** (best, when a feed includes it),
2. **Photogrammetry / Apple Object Capture / Gaussian-splat scanning** of the real piece ([AR Code](https://ar-code.com/blog/download-3d-scanning-photogrammetric-3d-models-in-glb-and-usdz)),
3. **CGI modelling** from photos + dimensions ([cgifurniture ROI](https://cgifurniture.com/blog/why-3d-modeling-is-important-for-e-commerce/) · [orbe3d guide](https://www.orbe3d.com/the-complete-guide-to-3d-furniture-models/)).

ROI is strongest when order value is high and returns matter — start with the
**top-selling SKUs**, not the whole catalog. This ties directly into the catalog
data pipeline (`datasets/EXTRACTION_PROMPT.md`): add two fields per product.

## 4) Data-model change (small, additive)
Add to `CatalogProduct` / the extraction schema:
```
model_glb_url  : string | null   // Android + web + WebXR
model_usdz_url : string | null   // iOS Quick Look
ar_ready       : bool            // both present + validated at real scale
```
Show the AR button only when `ar_ready`. Everything else (2D image, decision
loop) is unchanged.

## 5) Phasing
- **P1 — Proof:** `<model-viewer>` on product detail with **3–5 demo models**; real-size AR on iOS + Android; no install.
- **P2 — Coverage:** 3D pipeline for top SKUs; `model_*_url` in the Curated Release; validate scale vs catalog W/D/H.
- **P3 — Rich:** native ARKit/ARCore for **multi-item room layout + occlusion + save/share the scene**; feed room dimensions from Room Intelligence.

---

## 6) IMPLEMENTATION PROMPT (hand this to an agent)

> **Goal:** add a "**شاهدها في غرفتك**" (See it in your room) button to the product
> detail screen of this Flutter **web** app that opens real-size AR in the phone's
> browser — no app install.
>
> **Approach:** use Google's **`<model-viewer>`** web component. In Flutter web,
> register a platform view (`HtmlElementView` via `platformViewRegistry`) that
> hosts a `<model-viewer>` element, OR route to a lightweight standalone
> `ar.html` page passing the product id. Configure:
> ```html
> <model-viewer
>   src="{model_glb_url}"            <!-- Android/web -->
>   ios-src="{model_usdz_url}"       <!-- iOS Quick Look -->
>   ar ar-modes="webxr scene-viewer quick-look"
>   ar-scale="fixed"                 <!-- real-world size, no resize -->
>   camera-controls shadow-intensity="1"
>   alt="{title}"></model-viewer>
> ```
> **Rules:** (1) show the AR button only when `ar_ready` is true; else show the
> 2D image with "3D قريبًا". (2) Models are authored in **meters at real scale**,
> so `ar-scale="fixed"` shows true size — verify against the catalog `width/depth/
> height_cm`. (3) Load `@google/model-viewer` from a bundled/self-hosted script
> (CSP-safe), not an ad-hoc CDN in production. (4) Test matrix: **iOS Safari**
> (Quick Look via USDZ) and **Android Chrome** (Scene Viewer/WebXR via GLB).
> (5) Keep it behind the existing feature-flag/DI pattern; no change to the
> domain engine. (6) Add `model_glb_url`, `model_usdz_url`, `ar_ready` to
> `CatalogProduct` (+ `fromJson`/`toJson`) — additive.
> **Deliver:** the AR view/button, the model fields, a graceful fallback, and a
> short doc on how to run it on a device. Verify the web build stays green in CI.

## 7) 3D-ASSET PIPELINE PROMPT (hand this to a 3D/ops agent)

> For each **priority SKU**, produce a **GLB** (Android/web) **and** a **USDZ**
> (iOS), each **< 5 MB**, **authored at real-world scale in meters** matching the
> catalog `width/depth/height_cm`, with correct colour and material. Source order:
> (a) supplier-provided 3D, else (b) **photogrammetry / Object Capture** of the
> real item, else (c) **CGI** from front/side/top photos + dimensions. **Validate
> each model:** bounding box == catalog dimensions (±2 cm); base colour matches
> `color_tags`; poly count reasonable; file < 5 MB; opens in Quick Look (iOS) and
> Scene Viewer (Android). Store in object storage with signed URLs; write
> `model_glb_url` + `model_usdz_url` + `ar_ready:true` back to the product record.
> **Never** publish a model whose scale isn't verified — a wrong-size AR preview
> destroys the trust the whole product is built on.

---

## 8) Honest status
This is **researched and specified, not built.** I can build **P1** (the
`<model-viewer>` AR button + a couple of free demo models) as a proof — but real
"see *this* sofa in your room" needs a **3D model per product**, which is a data/
ops investment (scan or model each SKU), not something this sandbox can generate.
The prompts above make both halves executable the moment you have 3D assets.
