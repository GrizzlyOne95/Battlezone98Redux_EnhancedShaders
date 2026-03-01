void occlusion_vertex(
	uniform float4x4 wvpMat,

	in float4 iPosition : POSITION,
	in float4 iColor : COLOR0,

	out float4 vColor : COLOR0,
	out float4 oPosition : SV_POSITION
	)
{
	oPosition = mul(wvpMat, iPosition);
	vColor = iColor.bgra;
}

// -------------------------------------------

void occlusion_fragment(
	in float4 vColor : COLOR0,

	out float4 oColor : SV_TARGET
	)
{
	oColor = vColor;
}
