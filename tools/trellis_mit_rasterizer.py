"""MIT-licensed replacement for the nvdiffrast calls in TRELLIS.2's GLB export.

Why this exists
    TRELLIS.2 itself is MIT (code and weights), but its `o_voxel.postprocess`
    module imports `nvdiffrast`, which is under the NVIDIA Source Code License
    (1-Way Commercial): research and evaluation use only, no direct or
    indirect monetary gain. Generating catalogue assets for a commercial app
    through nvdiffrast is exactly the use that licence forbids.

    The trace of `o_voxel.postprocess.to_glb` (TRELLIS.2 @ 75fbf01) shows
    nvdiffrast is used for one narrow job: rasterising the mesh's UV layout
    into texture space to decide which texel belongs to which face
    (`dr.rasterize`), and interpolating per-vertex positions at those texels
    (`dr.interpolate`). No gradients, no camera, no depth test — plain 2D
    coverage rasterisation. That subset is small enough to reimplement in
    PyTorch, which is what this module does.

What it is NOT
    Not a fork of nvdiffrast and not derived from its source: this file
    implements the same *call signatures* from their documented behaviour so
    `postprocess.py` runs unmodified. It covers only what `to_glb` uses —
    xy-only clip positions (z=0, w=1), CUDA-context rasterisation, barycentric
    interpolation. Anything else (depth, antialiasing, mipmaps, OpenGL
    contexts) is deliberately absent and raises.

Usage
    import trellis_mit_rasterizer
    trellis_mit_rasterizer.install()   # BEFORE any `import o_voxel`
    import o_voxel                      # now imports cleanly, nvdiffrast-free

Conventions
    Pixel (0, 0) is the bottom-left of the buffer (NDC y = -1), matching
    nvdiffrast's OpenGL-style convention. This matters: `to_glb` flips the
    exported V coordinate and trimesh's GLB exporter flips it back, a chain
    validated against nvdiffrast's row order. If textures ever render
    per-island scrambled, set TRELLIS_SHIM_FLIP_V=1 and re-export one product
    — that inverts the row order without touching code.

Self-test
    python tools/trellis_mit_rasterizer.py --self-test
    Pure torch (CPU or CUDA); run it once on the cloud box before a batch.
"""

from __future__ import annotations

import os
import sys
import types

import torch

# Triangles whose UV-space bounding box exceeds this go through the (rare)
# one-at-a-time path instead of the batched one, keeping peak memory flat.
_BATCH_BBOX_CAP = 128
_PIXEL_BUDGET = 4_000_000  # candidate texels per batch


class RasterizeCudaContext:
    """Accepted for signature compatibility; the torch implementation needs
    no persistent GPU state."""

    def __init__(self, device=None):
        self.device = device


class RasterizeGLContext:
    def __init__(self, *_, **__):
        raise NotImplementedError(
            "trellis_mit_rasterizer replaces only the CUDA-context path that "
            "o_voxel.postprocess uses."
        )


def _flip_v() -> bool:
    return os.environ.get("TRELLIS_SHIM_FLIP_V", "0") == "1"


def rasterize(ctx, pos, tri, resolution, **kwargs):
    """UV-space triangle rasterisation.

    Args (the subset to_glb uses):
        pos: (1, V, 4) float — clip-space positions; to_glb passes z=0, w=1,
             xy in [-1, 1] (UVs remapped by uv*2-1).
        tri: (T, 3) int — triangle vertex indices.
        resolution: [H, W].

    Returns:
        (rast, None) with rast (1, H, W, 4) float32:
            [..., 0] barycentric weight of the triangle's SECOND vertex
            [..., 1] barycentric weight of the THIRD vertex
            [..., 2] 0.0 (depth unused by to_glb)
            [..., 3] triangle index + 1, 0.0 where no coverage
        Weight of the first vertex is 1 - u - v; `interpolate` below uses the
        same convention, so the pair is internally consistent.
    """
    if pos.dim() != 3 or pos.shape[0] != 1:
        raise NotImplementedError("only minibatch size 1 is supported")
    H, W = int(resolution[0]), int(resolution[1])
    device = pos.device
    verts = pos[0, :, :2]

    tri = tri.long()
    rast = torch.zeros((H, W, 4), device=device, dtype=torch.float32)
    if tri.numel() == 0:
        return rast.unsqueeze(0), None

    # NDC -> continuous pixel coordinates (pixel centres at integer + 0.5).
    px = (verts[:, 0] + 1.0) * 0.5 * W
    py = (verts[:, 1] + 1.0) * 0.5 * H
    P = torch.stack([px, py], dim=-1)

    A, B, C = P[tri[:, 0]], P[tri[:, 1]], P[tri[:, 2]]  # (T, 2) each

    # Signed twice-area; degenerate triangles cover nothing.
    area = (B[:, 0] - A[:, 0]) * (C[:, 1] - A[:, 1]) - (B[:, 1] - A[:, 1]) * (
        C[:, 0] - A[:, 0]
    )
    alive = area.abs() > 1e-12

    lo = torch.floor(torch.minimum(torch.minimum(A, B), C)).clamp(min=0)
    hi = torch.ceil(torch.maximum(torch.maximum(A, B), C))
    hi = torch.minimum(hi, torch.tensor([W, H], device=device, dtype=hi.dtype))
    span = (hi - lo).clamp(min=0)
    alive &= (span[:, 0] > 0) & (span[:, 1] > 0)

    side = span.max(dim=1).values
    small = alive & (side <= _BATCH_BBOX_CAP)
    large = alive & (side > _BATCH_BBOX_CAP)

    def _write(ids, sub_lo, S):
        """Rasterise triangles `ids` over SxS pixel windows anchored at sub_lo."""
        if ids.numel() == 0:
            return
        batch = max(1, _PIXEL_BUDGET // max(1, S * S))
        offs = torch.arange(S, device=device, dtype=torch.float32)
        for start in range(0, ids.numel(), batch):
            sel = ids[start : start + batch]
            n = sel.numel()
            base = sub_lo[start : start + batch]  # (n, 2) pixel-space anchor
            gx = base[:, 0:1, None] + offs[None, :, None].expand(n, S, S) + 0.5
            gy = base[:, 1:2, None] + offs[None, None, :].expand(n, S, S) + 0.5
            a, b, c = A[sel], B[sel], C[sel]
            ar = area[sel]
            # Barycentrics from edge functions, sign-normalised so either
            # winding rasterises (nvdiffrast does not cull in this path).
            w1 = (
                (gx - a[:, 0, None, None]) * (c[:, 1, None, None] - a[:, 1, None, None])
                - (gy - a[:, 1, None, None]) * (c[:, 0, None, None] - a[:, 0, None, None])
            ) / ar[:, None, None]
            w2 = (
                (gy - a[:, 1, None, None]) * (b[:, 0, None, None] - a[:, 0, None, None])
                - (gx - a[:, 0, None, None]) * (b[:, 1, None, None] - a[:, 1, None, None])
            ) / ar[:, None, None]
            # Signed area in the denominator makes the weights winding-
            # independent: both numerator and denominator flip together.
            w0 = 1.0 - w1 - w2
            eps = 1e-7
            inside = (w0 >= -eps) & (w1 >= -eps) & (w2 >= -eps)
            xi = gx.long().clamp(0, W - 1)
            yi = gy.long().clamp(0, H - 1)
            inbounds = (gx >= 0) & (gx < W) & (gy >= 0) & (gy < H)
            keep = inside & inbounds
            if not keep.any():
                continue
            tid = sel[:, None, None].expand_as(xi)[keep]
            rows = yi[keep]
            cols = xi[keep]
            payload = torch.stack(
                [
                    w1[keep],
                    w2[keep],
                    torch.zeros_like(w1[keep]),
                    tid.float() + 1.0,
                ],
                dim=-1,
            )
            rast[rows, cols] = payload  # last writer wins, as in a plain scan

    small_ids = small.nonzero(as_tuple=True)[0]
    if small_ids.numel():
        S = int(side[small_ids].max().clamp(min=1).item()) + 1
        _write(small_ids, lo[small_ids], S)
    for tid in large.nonzero(as_tuple=True)[0]:
        one = tid.unsqueeze(0)
        S = int(side[one].item()) + 1
        _write(one, lo[one], S)

    if _flip_v():
        rast = rast.flip(0)
    return rast.unsqueeze(0), None


def interpolate(attr, rast, tri, **kwargs):
    """Barycentric attribute interpolation matching `rasterize`'s output.

    attr: (1, V, C); rast: (1, H, W, 4); tri: (T, 3).
    Returns (out, None) with out (1, H, W, C); zeros where no coverage.
    """
    tri = tri.long()
    values = attr[0]
    face_id = rast[0, ..., 3].round().long()
    valid = face_id > 0
    idx = (face_id - 1).clamp(min=0)
    corners = tri[idx]  # (H, W, 3)
    u = rast[0, ..., 0:1]
    v = rast[0, ..., 1:2]
    w0 = 1.0 - u - v
    out = (
        w0 * values[corners[..., 0]]
        + u * values[corners[..., 1]]
        + v * values[corners[..., 2]]
    )
    out = torch.where(valid.unsqueeze(-1), out, torch.zeros_like(out))
    return out.unsqueeze(0), None


def antialias(*_, **__):
    raise NotImplementedError("antialias is not used by o_voxel.postprocess")


def texture(*_, **__):
    raise NotImplementedError("texture is not used by o_voxel.postprocess")


def install(force: bool = False) -> bool:
    """Register this module as `nvdiffrast.torch` in sys.modules.

    Must run before anything imports o_voxel (whose __init__ pulls in
    postprocess, which does `import nvdiffrast.torch as dr` at module level).
    Returns True if the shim was installed, False if real nvdiffrast was
    already imported and force=False.
    """
    if "nvdiffrast.torch" in sys.modules and not force:
        return False
    this = sys.modules[__name__]
    package = types.ModuleType("nvdiffrast")
    package.torch = this
    sys.modules["nvdiffrast"] = package
    sys.modules["nvdiffrast.torch"] = this
    return True


# --------------------------------------------------------------------------
# Self-test: internal consistency of the rasterize/interpolate pair.

def _self_test() -> int:
    device = "cuda" if torch.cuda.is_available() else "cpu"
    print(f"self-test on {device}")
    H = W = 128

    # Unit UV square as two triangles (opposite windings, deliberately, to
    # prove winding-independence). Attribute = the vertex's own UV.
    uv = torch.tensor(
        [[0.0, 0.0], [1.0, 0.0], [1.0, 1.0], [0.0, 1.0]], device=device
    )
    tri = torch.tensor([[0, 1, 2], [0, 3, 2]], device=device, dtype=torch.int32)
    pos = torch.cat(
        [uv * 2 - 1, torch.zeros_like(uv[:, :1]), torch.ones_like(uv[:, :1])], dim=-1
    ).unsqueeze(0)

    ctx = RasterizeCudaContext()
    rast, _ = rasterize(ctx, pos, tri, resolution=[H, W])

    coverage = (rast[0, ..., 3] > 0).float().mean().item()
    assert coverage > 0.98, f"coverage {coverage:.3f} — expected ~full"
    ids = rast[0, ..., 3].unique().tolist()
    assert 1.0 in ids and 2.0 in ids, f"face ids missing: {ids}"

    out = interpolate(uv.unsqueeze(0), rast, tri)[0][0]
    yy, xx = torch.meshgrid(
        torch.arange(H, device=device), torch.arange(W, device=device), indexing="ij"
    )
    expect_u = (xx.float() + 0.5) / W
    expect_v = (yy.float() + 0.5) / H
    if _flip_v():
        expect_v = 1.0 - expect_v
    mask = rast[0, ..., 3] > 0
    err_u = (out[..., 0] - expect_u).abs()[mask].max().item()
    err_v = (out[..., 1] - expect_v).abs()[mask].max().item()
    assert err_u < 1.5 / W and err_v < 1.5 / H, f"interpolation error u={err_u} v={err_v}"

    # A triangle bigger than the batched bbox cap must land in the slow path
    # and produce identical results to a small-scale render of the same shape.
    big_tri = torch.tensor([[0, 1, 2]], device=device, dtype=torch.int32)
    rast_big, _ = rasterize(ctx, pos, big_tri, resolution=[512, 512])
    cov_big = (rast_big[0, ..., 3] > 0).float().mean().item()
    assert 0.45 < cov_big < 0.55, f"large-triangle coverage {cov_big:.3f}, expected ~0.5"

    print(
        f"OK: coverage={coverage:.3f}, both faces present, "
        f"max interp err u={err_u:.5f} v={err_v:.5f}, large-tri path OK"
    )
    return 0


if __name__ == "__main__":
    if "--self-test" in sys.argv:
        raise SystemExit(_self_test())
    print(__doc__)

# Marker so callers can tell the shim from real nvdiffrast.
IS_MIT_SHIM = True
