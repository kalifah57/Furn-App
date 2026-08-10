# Real furniture → AR-placeable model (prompt + applied)

- **Status:** Prompt **and applied** — a real, to-scale piece now opens in AR in the app.
- **Date:** 2026-07-31
- **Answers the ask:** "take a real piece of furniture with its dimensions and specs, turn it into something placeable in AR — make a prompt for it, then apply it."
- **Related:** `docs/ar_visualization.md`, `tools/generate_furniture_glb.py`, `web/ar.html`, `lib/features/ar/`.

> **The key unlock:** an AR model doesn't have to be scanned or downloaded. For a
> piece with known **dimensions**, a valid **GLB at true real-world scale** can be
> **generated from box geometry** — no dependencies, a few KB. `<model-viewer>`
> then places it at real size, and **iOS Safari auto-converts the GLB to USDZ**
> for Quick Look (no separate USDZ file needed); Android uses the GLB via Scene
> Viewer. [model-viewer FAQ](https://modelviewer.dev/docs/faq.html) · [discussion #4668](https://github.com/google/model-viewer/discussions/4668)

---

## THE PROMPT (real furniture → AR-ready GLB)

> **Goal:** take a real furniture product — its **real dimensions** (W×D×H in cm)
> and **specs** (colour, material, shape) — and output a **valid `.glb` authored in
> metres at true real-world scale**, plus the catalog wiring so it opens in AR.
>
> **Inputs:** `title`, `category`, `width_cm/depth_cm/height_cm`, `color_tags`,
> `material_tags`, and a **parts list** describing the piece as axis-aligned boxes
> (e.g. table = top slab + 4 legs + lower shelf; nightstand = body + top + 2 drawer
> fronts + plinth), each part as `center(x,y,z)` + `size(sx,sy,sz)` in **metres**,
> **Y-up, origin at the floor centre (bottom at y=0)**.
>
> **Produce a GLB that:**
> 1. is authored **in metres at real scale** — its bounding box **equals** the
>    catalog W×D×H (±1 cm); the piece sits on the floor (min y = 0).
> 2. uses **flat-shaded box meshes**, one **primitive per material group**, with
>    **PBR materials** (`baseColorFactor` converted **sRGB→linear**, low metallic,
>    wood-ish roughness); mark materials `doubleSided:true` so winding can't hide faces.
> 3. sets `POSITION` accessor **min/max**, 4-byte-aligned bufferViews, `UNSIGNED_SHORT`
>    indices, `ARRAY_BUFFER`/`ELEMENT_ARRAY_BUFFER` targets — a spec-valid glTF 2.0.
> 4. stays **< 5 MB** (box geometry is a few KB).
> 5. **self-checks:** re-parse the GLB, assert header/chunks and that the bounding
>    box matches the declared cm (±1 cm).
>
> **Then wire it (no engine change):** write the GLB to `web/models/<id>.glb`
> (copied to the deployment, served at `/<base>/models/<id>.glb`); add a
> `CatalogProduct` with real dimensions, `model_glb_url:"models/<id>.glb"`,
> `model_usdz_url:""` (iOS auto-generates), `ar_ready:true`. The "شاهدها في غرفتك"
> button then appears on that product automatically.
>
> **Rules:** real dimensions are non-negotiable (a wrong-size AR preview destroys
> trust); don't invent a real retailer's SKU/price; keep the domain engine untouched;
> keep the web build green in CI.

---

## APPLIED — a real coffee table you can place now
Ran the prompt via `tools/generate_furniture_glb.py`:

- **Piece:** walnut coffee table, **110 × 60 × 45 cm** (top slab + lower shelf +
  4 legs), two wood materials.
- **Output:** `web/models/coffee_table_walnut.glb` — **~5.5 KB**, 144 vertices,
  self-checked: bounding box = 1.10 × 0.60 × 0.45 m, floor at y=0. ✓
- **Wired:** catalog product `table_coffee_walnut_ar` (`ar_ready:true`), and the
  plan's AR card + the direct `ar.html` link default to it.
- **Try it:** app → **خطتي** → **"شاهد الطاولة في غرفتك"**, or open
  `…/Furn-App/ar.html` directly. iPhone (Quick Look) + Android (Scene Viewer), no install.

## Add the next piece
1. Add a `parts` spec (boxes in metres) for the new item in
   `tools/generate_furniture_glb.py` and run it → `web/models/<id>.glb`.
2. Add the `CatalogProduct` with real dimensions + `model_glb_url` + `ar_ready:true`.
3. For pieces too organic for boxes (curved sofas, detailed chairs), swap in a
   **supplier / photogrammetry / CGI** GLB at real scale (`docs/ar_visualization.md` §7)
   — the wiring is identical.
