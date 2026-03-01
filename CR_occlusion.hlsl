void occlusion_vertex(
	uniform float4x4 wvpMat,

	in float4 iPosition : POSITION,
	in float4 iColor : COLOR0,

	out float4 vColor : COLOR0,
	out float4 oPosition : POSITION
	)
{
	oPosition = mul(wvpMat, iPosition);
	vColor = iColor;
}

// -------------------------------------------

void occlusion_fragment(
	in float4 vColor : COLOR0,

	out float4 oColor : COLOR
	)
{
	oColor = vColor;
}
