# Enhanced Shaders

Material, shader, and rendering-profile addon content for Battlezone 98 Redux.

## High-Level Summary

- Conservative stock-derived `CR_*` shader/material fork that remaps the addon
  content stack onto shared base, cockpit, and terrain shader families instead
  of trying to replace the renderer wholesale.
- Shared safety hardening across DX9, DX11, and GL, with guarded normalize,
  lighting, and spot calculations aimed at reducing renderer instability from
  fragile shader math.
- Terrain correctness fixes aimed at the stock terrain deformation issue,
  specifically atlas texel-center sampling and safer packed-normal
  reconstruction.
- Optional retro-lighting compatibility through the `og-*` material schemes used
  by the addon stack and exposed through EXU.
- Intentionally scoped to a stability-first pass: no skinning additions in the
  current branch, and visuals stay close to stock until the baseline is proven.

Current shader pass:
- conservative stock-derived `CR_*` material/shader fork
- shared DX9, DX11, and GL safety hardening
- terrain atlas texel-center and packed-normal fixes aimed at stock terrain deformation issues
- optional OG retro-lighting compatibility through the `og-*` material schemes used by the addon stack

See [`ISSUE_TRIAGE.md`](ISSUE_TRIAGE.md) for the current rationale and issue-by-issue status for this pass.
