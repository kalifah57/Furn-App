# TRELLIS.2 Pipeline — High-Fidelity 3D on a Rented CUDA GPU

`tools/generate_3d_trellis.py` is the CUDA counterpart of the SF3D pipeline:
same `Catalog_Fin/catalog.json` in, same `Assets/3D_Models/*.glb` +
`Catalog_Fin/3D_Catalog_new.json` registry out, same true-scale conversion —
but the model is Microsoft's **TRELLIS.2-4B**, run at maximum fidelity
(1536 cascade, 4K PBR textures, remeshing on). It exists because SF3D's
geometry is a 2024 speed-first model; TRELLIS.2 is the current
state of the art among open-weight image-to-3D models.

It does not run on a Mac. Target: a rented **A100/H100-class instance**
(Ubuntu 22.04, NVIDIA driver with CUDA 12.4 support, ≥24 GB VRAM — the
figure TRELLIS.2's README verifies against).

## ⚖️ The licence position (read before commercial use)

Traced against TRELLIS.2 @ `75fbf01` (June 2026), file by file:

| Component | Licence | In the image→GLB path? |
| --- | --- | --- |
| TRELLIS.2 code + 4B weights | MIT | yes |
| o-voxel (in-repo extension) | MIT (part of the repo) | yes |
| CuMesh, FlexGEMM (author's extensions) | MIT | yes |
| BiRefNet background matting | MIT weights, via transformers | yes |
| **nvdiffrast** | **NVIDIA 1-Way Commercial** | **one call site: UV texel rasterisation inside `o_voxel.postprocess.to_glb`** |
| nvdiffrec | NVIDIA 1-Way Commercial | no — preview renderer only, lazily imported, never loaded by this adapter |

The NVIDIA licence's §3.3 restricts use to "research or evaluation purposes
only and not for any direct or indirect monetary gain". Generating catalogue
assets for a commercial app through nvdiffrast is squarely what that
excludes. Two facts make the problem tractable:

1. The **geometry pipeline is clean**: `pipeline.run()` touches only
   MIT-licensed code (verified — no nvdiffrast/nvdiffrec anywhere in
   `trellis2/pipelines`, `modules`, `representations`, or the samplers, and
   every TRELLIS.2 subpackage lazy-loads, so the renderers never import).
2. The **one nvdiffrast call site is not differentiable rendering** — it
   rasterises the UV layout to decide which texel belongs to which face, and
   interpolates positions there. No gradients, no camera, no depth.

So this pipeline ships `tools/trellis_mit_rasterizer.py`: an MIT-licensed
PyTorch implementation of exactly that subset (`rasterize` + `interpolate`,
written against the documented interface, not derived from NVIDIA source).
The adapter installs it **before** anything imports `o_voxel`, so
**nvdiffrast is neither installed nor imported on the commercial path** —
`setup.sh`'s `--nvdiffrast`/`--nvdiffrec` flags are simply never used.

`--allow-nvdiffrast` exists for research/evaluation comparison runs; assets
generated with it must not be shipped.

**Scope of this analysis**: this is an engineering trace of what code
executes, current as of the commit above and thorough enough to build on —
but it is not legal advice, and upstream can move the boundary in either
direction (see the open clarification request,
[TRELLIS.2 issue #22](https://github.com/microsoft/TRELLIS.2/issues/22)).
Have counsel confirm before betting the product on it, and re-run the trace
(`grep -rn nvdiffrast` over the checkout) after any TRELLIS.2 update.

## Instance setup (once per instance)

Assumes a fresh Ubuntu 22.04 GPU instance with the NVIDIA driver installed
(`nvidia-smi` works and reports CUDA ≥ 12.4).

### 1. System packages and repo

```bash
sudo apt-get update && sudo apt-get install -y git python3-venv python3-dev build-essential
git clone https://github.com/kalifah57/Furn-App && cd Furn-App
git checkout claude/local-3d-furniture-pipeline-k2fvp1
git clone --recursive https://github.com/microsoft/TRELLIS.2 vendor/TRELLIS.2
```

(`--recursive` matters: o-voxel builds against a vendored Eigen submodule.)

### 2. Python environment + torch (cu124 wheels first)

```bash
python3 -m venv .venv-trellis
source .venv-trellis/bin/activate
pip install --upgrade pip
pip install torch==2.6.0 torchvision==0.21.0 --index-url https://download.pytorch.org/whl/cu124
python -c "import torch; print(torch.cuda.get_device_name(0))"
```

### 3. Dependencies + the three MIT CUDA extensions

```bash
pip install -r tools/requirements-trellis.txt
pip install flash-attn==2.7.3 --no-build-isolation

git clone --recursive https://github.com/JeffreyXiang/CuMesh /tmp/CuMesh
pip install /tmp/CuMesh --no-build-isolation
git clone --recursive https://github.com/JeffreyXiang/FlexGEMM /tmp/FlexGEMM
pip install /tmp/FlexGEMM --no-build-isolation
pip install vendor/TRELLIS.2/o-voxel --no-build-isolation
```

Do **not** run TRELLIS.2's `setup.sh --nvdiffrast` or `--nvdiffrec` — that
is the licence line. The extension builds compile CUDA kernels and take
several minutes each; `--no-build-isolation` makes them build against the
torch you just installed.

### 4. Validate the MIT rasteriser, once

```bash
python tools/trellis_mit_rasterizer.py --self-test
```

Must print `OK`. (Also runs on CPU torch, so you can pre-check it on the
Mac before renting anything.) If, on the first real product, textures render
per-island scrambled in the viewer, set `TRELLIS_SHIM_FLIP_V=1` and
regenerate one product — that flips the bake's row order, the one convention
that cannot be proven without a visual check.

### 5. The catalogue

`catalog.json` is git-ignored, so bring it from your Mac:

```bash
scp Catalog_Fin/catalog.json <user>@<instance>:~/Furn-App/Catalog_Fin/
```

(or generate it on the instance — see `tools/README_3D.md` step 6).

## Running

```bash
python tools/generate_3d_trellis.py --limit 1     # smoke test
python tools/generate_3d_trellis.py               # full catalogue
```

First run downloads ~10 GB of weights (TRELLIS.2-4B + BiRefNet) into
`~/.cache/huggingface`. Models are public — no Hugging Face login needed,
unlike SF3D.

Defaults are tuned for **maximum quality, not speed**: `1536_cascade`
resolution path, 4096px PBR texture atlas, 1M-vertex decimation budget,
remeshing on, and the pipeline's own tuned sampler steps. Expect roughly a
minute per product on an A100 — for a 50-product catalogue, the GPU-hour
cost is trivial next to the quality difference.

Everything the SF3D adapter does about robustness applies unchanged:
per-product failures land in `Catalog_Fin/3D_Catalog_failures.json` and the
loop continues; runs are resumable (`--force` regenerates); the registry is
rebuilt from the full catalogue every run; meshes are scaled to the
catalogue's `spatial_attributes` (metres, x=W/y=H/z=D, floor at y=0,
verified to 1 cm) unless `--no-scale`.

Flags beyond the shared set:

| Flag | Default | Purpose |
| --- | --- | --- |
| `--pipeline-type` | `1536_cascade` | Resolution path; `1024` is the fallback for <40 GB VRAM |
| `--steps N` | pipeline defaults | Sampler steps for all three stages (50 is the samplers' own default) |
| `--guidance X` | pipeline defaults | Guidance strength override |
| `--texture-size` | 4096 | Baked PBR atlas size |
| `--decimation-target` | 1,000,000 | Vertex budget after decimation |
| `--no-remesh` | off | Skip remeshing (faster, worse topology) |
| `--max-tokens` | 49152 | Cascade token budget |
| `--low-vram` | off | Offload the matting model between products |
| `--allow-nvdiffrast` | off | Research/evaluation bake via NVIDIA nvdiffrast |

## Getting the results back

```bash
scp -r <user>@<instance>:~/Furn-App/Assets/3D_Models Assets/
scp <user>@<instance>:~/Furn-App/Catalog_Fin/3D_Catalog_new.json Catalog_Fin/
```

Then inspect locally exactly as with SF3D output:

```bash
python -m http.server 8000    # from the repo root on the Mac
# open http://localhost:8000/tools/view_3d.html
```

The two adapters write the same filenames into the same registry, so
regenerating a product with TRELLIS.2 replaces its SF3D mesh (`--force`) and
the app needs no changes to consume either.
