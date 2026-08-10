# Design heuristics — sourced acceptance-criteria library

Real, cited furnishing heuristics gathered in the Research phase. They are the
raw material for `acceptance_criteria` (what makes a recommendation *good*). Each
is tagged by how it can be checked:

- **[machine-now]** — the runner can already check it (see `constraints/catalog.md`).
- **[machine-future]** — checkable once the **Measurement Engine** lands (spatial math); until then it's a human criterion.
- **[human]** — expert judgment; stays in `acceptance_criteria.human`.

> Honesty note: these came from design guides, **not** from real user cases.
> US-only web search surfaced guidelines, not quote-able posts — so this file
> seeds the *rubric*, and canonical *cases* must still be collected from real
> request threads (see `PIPELINE_PROMPT.md`).

## Spatial / fit
| Heuristic | Value | Check |
|---|---|---|
| Walking clearance in pathways | **76–91 cm** (30–36 in) | [machine-future] · [human] now |
| Face-to-face seating distance | **≤ ~244 cm** (8 ft) | [machine-future] |
| Bed approachable from **both** sides | clearance each side | [machine-future] |
| Every piece must physically fit | fits direct or rotated | **[machine-now]** `fits_room` |
| Don't push all furniture to the walls | layout rule | [human] |

## Sizing / selection
| Heuristic | Note | Check |
|---|---|---|
| Small room → **loveseat / smaller sofa + accent chairs**, not a large sectional | 10–15 cm shorter seating reads roomier | [human] + **[machine-now]** via `excludes_product` (oversized) |
| Sofa depth ~**91 cm**; full sofa length **183–244 cm** | catalog sanity band | [machine-now] (dimension plausibility) |
| Exposed legs / raised furniture | reads more open in small rooms | [human] |
| Rug **sized to the seating** (not undersized) | grounds the arrangement | [human] |

## Budget / priority
| Heuristic | Note | Check |
|---|---|---|
| Swap coffee table → **ottomans** to save | cheaper + flexible | [human] |
| Buy **a few high-quality lasting pieces**; repurpose the rest | longevity over quantity | [human] |
| **Neutral** large pieces; colour via pillows/textiles | cheap refreshes | [human] |
| Never exceed the stated budget on a single item | sanity | **[machine-now]** `within_total_budget` |

## Sources
- [Chairish — decorate a small living room](https://www.chairish.com/blog/how-do-you-decorate-a-small-living-room/amp)
- [AOL — 7 ways to furnish on a tight budget](https://www.aol.com/finance/7-ways-quickly-furnish-space-170000840.html)
- [AOL — designers agree bigger isn't better (small-space sofas)](https://www.aol.com/interior-designers-agree-bigger-isnt-231500953.html)
- [Houzz — key measurements for your living room](https://www.houzz.com/magazine/key-measurements-for-your-living-room-stsetivw-vs~25889785)
- [iHome Studio — sofa size guide](https://ihome-studio.com/blogs/furniture-buying-guide/sofa-size-guide-what-dimensions-fit-your-living-room)
- [Apartment Therapy — arrange a small bedroom](https://www.apartmenttherapy.com/how-to-arrange-a-small-bedroom-255718)
- [AOL — 26 expert tips to arrange furniture](https://www.aol.com/lifestyle/26-expert-tips-help-arrange-105110378.html)
