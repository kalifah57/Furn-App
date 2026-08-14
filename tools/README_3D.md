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

## The meshes are true-scale

SF3D reconstructs into a normalised ±1 unit cube — no real-world size, no
floor. That is invisible in a model viewer and wrong in AR, where a 228 cm
sofa and a 55 cm side table would arrive the same size. So every mesh is
resized to the product's own `spatial_attributes` and seated on the ground,
to the contract `tools/generate_furniture_glb.py` already self-checks:

| Guarantee | Value |
| --- | --- |
| Units | metres |
| Axes | `x` = `width_cm`, `y` = `height_cm`, `z` = `length_cm` (front-to-back depth) |
| Floor | lowest vertex at `y = 0`, within 5 mm |
| Footprint | centred on the origin in `x`/`z` |
| Tolerance | each axis within 1 cm of the catalogue, verified after export |

Two details worth knowing:

- **Which way the mesh faces depends on the source photo.** The reconstruction
  can come back with its long side on either horizontal axis, so the mesh is
  turned a quarter turn when that would otherwise put depth on `x`. The turn
  is a real rotation about Y, never an axis swap — swapping is a reflection,
  and a reflected mesh renders inside out. The choice is made by which
  assignment needs the least stretching, not by which extent is larger:
  a 90×200 cm bed frame is deeper than it is wide, so "the bigger number is
  the width" is false exactly where it does damage.
- **A product with no usable dimensions is failed, not guessed at.** It lands
  in `3D_Catalog_failures.json` rather than entering the registry at an
  invented size. `--no-scale` opts out and emits SF3D's raw normalised mesh —
  fine for inspecting reconstruction quality, not placeable in AR.

When a mesh needs markedly uneven correction to reach its catalogued size
(more than 1.25× between the largest and smallest axis factor), the run
reports it. The catalogue dimension still wins — it is the authoritative
number — but a product that shows up here usually has a bad measurement
upstream rather than a bad reconstruction.

## Hardware expectations

SF3D's MPS support is officially **experimental**. Stability tested it on an
M1 Max with 64 GB; they recommend the CPU backend (`SF3D_USE_CPU=1`) on
machines with **less than 32 GB of unified memory**, because MPS currently
uses more memory than CUDA. Default settings need roughly 6 GB of GPU memory
per image. Expect roughly a minute per product on MPS, several on CPU.

Measured on a 16 GB Apple Silicon MacBook Pro: MPS at the default
`--texture-resolution 1024` exceeded five minutes for a single product and
made the machine noticeably sluggish — the memory pressure sends it into
swap. On 16 GB, run the pipeline like this instead:

```bash
SF3D_USE_CPU=1 python tools/generate_3d.py --texture-resolution 512
```

CPU avoids the second fp32 copy MPS keeps in unified memory, and halving the
texture atlas cuts the largest remaining allocation. Slower per product on
paper, but it does not contend with the rest of the system, which is the
difference that matters on a 16 GB machine.

First run also downloads about 6 GB of model weights in total — SF3D itself
(4.02 GB), a transformers image encoder (1.22 GB), OpenCLIP (605 MB) and
rembg's u2net (176 MB). All are cached afterwards.

## One-time setup

Everything below happens once, from the repository root on your Mac.

> **Run the steps one at a time and check each one.** Later steps depend on
> tools that earlier steps put on your `PATH`. Pasting the whole block at
> once on a machine that is missing one of them produces a cascade of
> `command not found` errors that all trace back to the first failure.

### 0. System prerequisites

A stock macOS install has none of these. Each is genuinely required: clang
and an OpenMP runtime to compile SF3D's two native extensions
(`texture_baker`, `uv_unwrapper`), and a Python 3.11 interpreter, which
macOS does not ship.

**0a. Xcode Command Line Tools** — provides clang:

```bash
xcode-select --install
```

This opens a GUI dialog; click **Install** and wait for it to finish (a few
minutes). It's already installed if this prints a path:

```bash
xcode-select -p
```

**0b. Homebrew** — macOS has no package manager of its own. Skip if
`brew --version` already works:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

The installer finishes by printing a **"Next steps"** section telling you to
add `brew` to your `PATH`. That step is not optional — without it every
later `brew` command fails with `command not found`. On Apple Silicon:

```bash
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
eval "$(/opt/homebrew/bin/brew shellenv)"
brew --version
```

(On an Intel Mac, Homebrew lives in `/usr/local` and is on the default
`PATH` already.)

**0c. The two packages:**

```bash
brew install libomp python@3.11
python3.11 --version
```

(Stability's README documents the alternative of installing the OpenMP
runtime from <https://mac.r-project.org/openmp/> into `/usr/local`, and
python.org publishes a 3.11 installer `.pkg` if you'd rather not use
Homebrew; either works. With Homebrew, the `CPATH`/`LIBRARY_PATH` exports in
step 4 tell clang where `libomp` lives.)

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

Activating the venv is what puts bare `python` and `pip` on your `PATH` —
macOS itself provides neither (only `python3`). Every command from here on
assumes the venv is active; your prompt shows `(.venv-3d)` when it is. In a
new terminal, re-run `source .venv-3d/bin/activate` before anything else.

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

`vendor/` is git-ignored, so this checkout stays out of the Furn-App repo. If
the directory already exists, the clone is done — skip this step rather than
re-running it.

### 4. Python dependencies + native extensions

```bash
pip install -r tools/requirements-3d.txt

LIBOMP=$(brew --prefix libomp)
echo "$LIBOMP"
export CPATH="$LIBOMP/include:$CPATH"
export LIBRARY_PATH="$LIBOMP/lib:$LIBRARY_PATH"
export CPPFLAGS="-Wno-invalid-specialization $CPPFLAGS"
export CXXFLAGS="-Wno-invalid-specialization $CXXFLAGS"

pip install --no-build-isolation vendor/stable-fast-3d/texture_baker/
pip install --no-build-isolation vendor/stable-fast-3d/uv_unwrapper/
```

The `echo` must print `/opt/homebrew/opt/libomp` before you go on — see the
note on empty command substitutions below.

`tools/requirements-3d.txt` mirrors SF3D's own pins (plus this pipeline's
`requests`/`tqdm`/`Pillow`), so the vendored code and the script agree on
every shared library. `--no-build-isolation` makes the extension builds use
the torch you just installed instead of an empty isolated build environment —
skipping it is the classic cause of `ModuleNotFoundError: No module named
'torch'` during install.

`-Wno-invalid-specialization` is required on Xcode 16.3 and newer. PyTorch's
vendored `c10/util/strong_type.h` specializes `std::is_arithmetic`, which the
C++ standard forbids; older Apple clang tolerated it, current clang makes it
a hard error. It fires on the first torch header, so **every** extension
built against torch 2.4.1 fails on a modern toolchain until the diagnostic is
switched off. The alternative root-cause fix is `pip install --upgrade torch
torchvision`, whose newer headers no longer violate the rule — SF3D's README
endorses running the latest PyTorch, so either path is supported.

Both extensions `#include <omp.h>` unconditionally, and Homebrew keeps
`libomp` **keg-only** — its headers live under `$(brew --prefix libomp)`
rather than on the compiler's default search path, so without those two
exports the build dies with `fatal error: 'omp.h' file not found`. `CPATH`
and `LIBRARY_PATH` are read by clang itself, which is why they're used here
in preference to `CPPFLAGS`/`LDFLAGS` — setuptools does not reliably
forward those to the C++ compile line under torch's `BuildExtension`.

Check the `echo` output rather than trusting the command substitution: if
`brew` isn't on your `PATH`, `$(brew --prefix libomp)` silently expands to
an empty string and the exports become useless `/include` and `/lib` paths.

(Upstream's documented alternative is the OpenMP runtime from
<https://mac.r-project.org/openmp/>, which installs into `/usr/local` —
already on clang's default search path, so it needs no exports at all.)

### 5. Hugging Face access (the model is gated)

1. Log in to Hugging Face and request access at
   <https://huggingface.co/stabilityai/stable-fast-3d>. The gate is the
   Stability AI Community License — free for research and for commercial use
   under US$1M annual revenue; check `LICENSE.md` on the model page if that
   threshold is close.
2. Create a **read** token at <https://huggingface.co/settings/tokens>.
3. Authenticate the environment:

```bash
huggingface-cli login
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
python tools/generate_3d.py --limit 2
python tools/generate_3d.py
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
| `--target-vertex-count N` | -1 | Reduce the mesh to roughly N vertices; needs `--remesh` |
| `--no-scale` | off | Emit SF3D's raw normalised mesh — **not AR-placeable** |
| `--no-image-upscale` | off | Download `image_url` verbatim instead of asking the CDN for a larger size |
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
- **Input images are upgraded where possible.** IKEA's CDN serves the same
  asset at several sizes behind an `f=` parameter, and the catalogue keeps
  whatever the search API returned — often a thumbnail. A larger variant is
  requested first, with the catalogued URL as fallback, so a CDN that rejects
  the parameter costs one wasted request and nothing else. SF3D squares every
  input to its own `cond_image_size` (printed at startup), and the run reports
  any product whose image came in below that — those reconstructions are
  detail-capped no matter what else you tune.

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| `command not found: brew` | Homebrew isn't installed, or its "Next steps" `PATH` line was skipped — see step 0b |
| `command not found: python3.11` | `brew install python@3.11` (step 0c) hasn't run, usually because `brew` itself was missing |
| `command not found: python` or `pip` | The venv isn't active — `source .venv-3d/bin/activate` (step 1). macOS ships neither name |
| `command not found: huggingface-cli` | It arrives with `huggingface-hub` in step 4; run steps in order, with the venv active |
| `401`/`403` or "gated" while loading the model | Accept the license on the model page, then `huggingface-cli login` with a read token |
| `'is_arithmetic' cannot be specialized` building either extension | Xcode 16.3+ vs torch 2.4.1 — set the `CPPFLAGS`/`CXXFLAGS` exports from step 4, or `pip install --upgrade torch torchvision` |
| `'omp.h' file not found` / `-lomp` link error building extensions | `brew install libomp`, then set the `CPATH`/`LIBRARY_PATH` exports from step 4 — and check `echo $(brew --prefix libomp)` is not empty |
| `Could not open requirements file: tools/requirements-3d.txt` | The pipeline lives on the `claude/local-3d-furniture-pipeline-k2fvp1` branch — `git fetch origin <branch> && git checkout <branch>` |
| `ModuleNotFoundError: No module named 'torch'` during step 4 | You skipped `--no-build-isolation`, or torch isn't installed in this venv |
| `ImportError: texture_baker not found` at run time | The two `pip install --no-build-isolation ...` commands in step 4 didn't complete |
| MPS out-of-memory / machine swapping hard | Run with `SF3D_USE_CPU=1`, or lower `--texture-resolution` to 512 |
| Textures come out unusually dark on MPS | Known open SF3D bug ([issue #37](https://github.com/Stability-AI/stable-fast-3d/issues/37)); regenerate the affected products with `SF3D_USE_CPU=1 python tools/generate_3d.py --force --only <id>` |
| Every image download fails | You're offline or behind a proxy; the catalogue's CDN links need direct HTTPS |
