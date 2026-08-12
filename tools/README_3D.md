# Local 3D Furniture Pipeline — Stable Fast 3D on Apple Silicon

`tools/generate_3d.py` turns every product in `Catalog_Fin/catalog.json` into a
textured 3D mesh with [Stability AI's Stable Fast 3D](https://github.com/Stability-AI/stable-fast-3d)
(SF3D), running entirely on your Mac. The GPU is used through PyTorch's `mps`
backend (Metal); the script falls back to `cpu` only when MPS is genuinely
unavailable, and never selects CUDA.

For each product it downloads the catalogue image, strips the background
(`rembg`), runs SF3D, and writes a `.glb`:

```
Assets/3D_Models/<product_name_slug>_<id>.glb    e.g. kivik_3_seat_sofa_s79482824.glb
Catalog_Fin/3D_Catalog_new.json                  the registry the app consumes
Catalog_Fin/3D_Catalog_failures.json             only written when something failed
```

The registry is a JSON array with exactly three keys per record:

```json
[
  {
    "internal_id": 1,
    "store_id": "s79482824",
    "local_3d_path": "Assets/3D_Models/kivik_3_seat_sofa_s79482824.glb"
  }
]
```

`internal_id` is sequential from 1 in catalogue order. It is rebuilt from disk
on every run, so re-running after a failure (or with `--force`) never
renumbers entries differently than a clean run would. One consequence: when a
previously-failed product is recovered on a later run, entries after it shift
down by one — treat `store_id` as the durable key, `internal_id` as a
per-file sequence number.

## Hardware expectations

SF3D's MPS support is officially **experimental**. Stability tested it on an
M1 Max with 64 GB; they recommend the CPU backend (`SF3D_USE_CPU=1`) on
machines with **less than 32 GB of unified memory**, because MPS currently
uses more memory than CUDA. Default settings need roughly 6 GB of GPU memory
per image. Expect roughly a minute per product on MPS, several on CPU.

## One-time setup

Everything below happens once, from the repository root on your Mac.

### 0. Native build prerequisites

The SF3D repo ships two small C++/Metal extensions (`texture_baker`,
`uv_unwrapper`) that compile locally and need clang plus an OpenMP runtime.
[Homebrew](https://brew.sh) is assumed throughout — install it first if
`brew` isn't on your PATH:

```bash
xcode-select --install          # Apple's clang toolchain (skip if present)
brew install libomp             # OpenMP runtime for -fopenmp
brew install python@3.11        # macOS ships no python3.11 of its own
```

(Stability's README documents the alternative of installing the OpenMP
runtime from <https://mac.r-project.org/openmp/> into `/usr/local`; either
works. With Homebrew, the `CPPFLAGS`/`LDFLAGS` exports in step 4 tell clang
where it lives.)

### 1. Python environment

Python 3.11 is the sweet spot for the pinned dependency set: `numpy 1.26.4`
and `torch 2.4.x` have arm64 wheels for it, and `gpytoolbox 0.2.0` (SF3D's
remesher) ships no wheels for newer Pythons, which turns install into a
source build. Stick to 3.10 or 3.11:

```bash
cd Furn-App
python3.11 -m venv .venv-3d
source .venv-3d/bin/activate
python -m pip install --upgrade pip
```

### 2. PyTorch first (MPS comes built in)

The regular PyPI wheels for macOS arm64 include Metal/MPS support — no
special index URL is needed. Torch must be installed **before** the SF3D
extensions because their `setup.py` files import it at build time:

```bash
pip install torch==2.4.1 torchvision==0.19.1
python -c "import torch; print('MPS available:', torch.backends.mps.is_available())"
```

That check must print `True` on an Apple Silicon Mac. (Stability recommends
PyTorch ≥ 2.4 for MPS; a newer stable release also works if you prefer.)

### 3. Vendor the SF3D source

SF3D is not on PyPI — the inference code lives in the GitHub repo, which the
script imports from a local checkout (default `vendor/stable-fast-3d`,
overridable with `--sf3d-dir` or `SF3D_DIR`):

```bash
git clone https://github.com/Stability-AI/stable-fast-3d vendor/stable-fast-3d
```

### 4. Python dependencies + native extensions

```bash
pip install -r tools/requirements-3d.txt

export CPPFLAGS="-I$(brew --prefix libomp)/include"
export LDFLAGS="-L$(brew --prefix libomp)/lib"
pip install --no-build-isolation vendor/stable-fast-3d/texture_baker/
pip install --no-build-isolation vendor/stable-fast-3d/uv_unwrapper/
```

`tools/requirements-3d.txt` mirrors SF3D's own pins (plus this pipeline's
`requests`/`tqdm`/`Pillow`), so the vendored code and the script agree on
every shared library. `--no-build-isolation` makes the extension builds use
the torch you just installed instead of an empty isolated build environment —
skipping it is the classic cause of `ModuleNotFoundError: No module named
'torch'` during install.

### 5. Hugging Face access (the model is gated)

1. Log in to Hugging Face and request access at
   <https://huggingface.co/stabilityai/stable-fast-3d>. The gate is the
   Stability AI Community License — free for research and for commercial use
   under US$1M annual revenue; check `LICENSE.md` on the model page if that
   threshold is close.
2. Create a **read** token at <https://huggingface.co/settings/tokens>.
3. Authenticate the environment:

```bash
huggingface-cli login        # or: export HF_TOKEN=hf_...
```

The weights (`model.safetensors`, ~4 GB) download automatically on the first
run and are cached in `~/.cache/huggingface` afterwards. (`rembg` similarly
downloads its background-removal weights to `~/.u2net` on first use.)

### 6. A catalogue to process

If `Catalog_Fin/catalog.json` doesn't exist yet, generate it (the
`furn_catalog` package lives inside `Catalog_Fin/`, so run it from there):

```bash
pip install -r Catalog_Fin/requirements.txt
playwright install chromium
(cd Catalog_Fin && python -m furn_catalog --limit 50 --out catalog.json -v)
```

The `playwright install chromium` step matters: the extractor needs the
browser retry to read IKEA's collapsible measurement panels, and
`Catalog_Fin/README.md` warns that a run without it emits approximately
nothing for IKEA.

## Running the pipeline

```bash
source .venv-3d/bin/activate
python tools/generate_3d.py --limit 2     # smoke test on two products first
python tools/generate_3d.py               # full run, with progress bar
```

The script sets `PYTORCH_ENABLE_MPS_FALLBACK=1` itself before importing
torch (SF3D requires it on MPS — a few ops fall back to CPU), so prefixing
the command with it manually is optional.

Useful flags:

| Flag | Default | Purpose |
| --- | --- | --- |
| `--limit N` | all | Only the first N products |
| `--only ID` | — | A single product, e.g. `--only s79482824` |
| `--force` | off | Regenerate meshes that already exist |
| `--texture-resolution N` | 1024 | Baked texture atlas size (2048 = slower, heavier) |
| `--remesh {none,triangle,quad}` | none | SF3D remeshing mode |
| `--catalog / --output-dir / --registry` | repo paths | Override any location |
| `--sf3d-dir PATH` | `vendor/stable-fast-3d` | Where the SF3D checkout lives |

Behaviour worth knowing:

- **Resumable.** Products whose `.glb` already exists are skipped; the
  registry is rebuilt in full at the end of every run.
- **Failures don't stop the loop.** A dead image URL, a download timeout, or
  an inference error records the product in
  `Catalog_Fin/3D_Catalog_failures.json` and moves on. Failed products are
  left out of the registry, and a half-written `.glb` is deleted rather than
  registered.
- **Memory-constrained Mac?** Force the CPU backend:
  `SF3D_USE_CPU=1 python tools/generate_3d.py`

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| `401`/`403` or "gated" while loading the model | Accept the license on the model page, then `huggingface-cli login` with a read token |
| `'omp.h' file not found` / `-lomp` link error building extensions | `brew install libomp` and re-export the `CPPFLAGS`/`LDFLAGS` from step 4 |
| `ModuleNotFoundError: No module named 'torch'` during step 4 | You skipped `--no-build-isolation`, or torch isn't installed in this venv |
| `ImportError: texture_baker not found` at run time | The two `pip install --no-build-isolation ...` commands in step 4 didn't complete |
| MPS out-of-memory / machine swapping hard | Run with `SF3D_USE_CPU=1`, or lower `--texture-resolution` to 512 |
| Textures come out unusually dark on MPS | Known open SF3D bug ([issue #37](https://github.com/Stability-AI/stable-fast-3d/issues/37)); regenerate the affected products with `SF3D_USE_CPU=1 python tools/generate_3d.py --force --only <id>` |
| Every image download fails | You're offline or behind a proxy; the catalogue's CDN links need direct HTTPS |
