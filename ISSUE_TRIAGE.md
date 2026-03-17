## Stock Shader Triage

Date: 2026-03-17

Scope:
- Conservative stock-derived shader/material fork.
- No skinning additions in this pass.
- Focused on DX11/DX9/GL stability and low-risk terrain correctness.

GitHub issues reviewed:

`#12` DX11 renderer very unstable
- Status: partially shader-fixable
- Likely shader-side risk areas were zero-length normalize/divide paths and packed terrain normal reconstruction.
- This pass hardens shared `base` and `terrain` shaders across DX9, DX11, and GL with safe normalization and guarded light/spot calculations.
- Not fully solved by shaders alone if the crash comes from texture loading, resource lifetime, or engine-side render-state bugs.

`#52` Terrain tile texture type 0 is deformed
- Status: shader-fixable
- Most likely cause is terrain atlas sampling at texel edges plus unsafe packed-normal reconstruction.
- This pass moves terrain atlas UVs to texel centers with a `+0.5` offset and clamps the reconstructed Y normal before `sqrt`.
- Priority: high

`#19` Graphical bugs on non-English localization
- Status: not shader-fixable
- Black or missing textures on localized installs strongly suggests asset lookup, filename, encoding, or loader behavior outside the shaders.
- Priority: engine/data investigation

`#59` Toggle tile blending from TRN
- Status: not implemented in this stock pass
- A material-level toggle is feasible later, but a true TRN toggle needs engine support or a reliable per-terrain input path.
- Priority: medium after the stability baseline is validated

`#77` Multiple atlases or terrain materials without a CSV
- Status: not shader-fixable
- This needs terrain material discovery/assignment changes in the engine or content pipeline.
- Priority: engine/content-system work

`#81` Improve Ogre rendering; flat lighting and normal maps
- Status: shader-fixable, but intentionally deferred
- The old repo had a much more aggressive custom lighting fork. This pass avoids that and keeps visuals near stock until the stability baseline is proven.
- Priority: medium after DX11/stability validation

What changed in this pass:
- Copied stock shaders/programs/materials into the custom `CR_*` stack.
- Repointed stock material imports and inheritance to `CR_BZBase` / `CR_BZTerrainBase`.
- Added safe normalization/guarded light math to shared `base` and `terrain` shaders in DX9, DX11, and GL.
- Applied the terrain texel-center and packed-normal clamp fix aimed at `#52`.
- Verified the HLSL stack with `tools/shader_smoke_test.ps1` and `fxc` across 150 permutations.
