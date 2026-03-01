float3 srgb_to_linear(float3 c) { return pow(max(c, 0.0), 2.2); }
float4 srgb_to_linear(float4 c) { return float4(pow(max(c.xyz, 0.0), 2.2), c.w); }
float3 linear_to_srgb(float3 c) { return pow(max(c, 0.0), 1.0 / 2.2); }
float4 linear_to_srgb(float4 c) { return float4(pow(max(c.xyz, 0.0), 1.0 / 2.2), c.w); }

void untextured_vertex(
	uniform float4x4 wvpMat,
	uniform float4 diffuseColor,

	in float4 iPosition : POSITION,
	in float4 iColor : COLOR0,

	out float4 vColor : COLOR0,
	out float vDepth : TEXCOORD1,

	out float4 oPosition : SV_POSITION
	)
{
	oPosition = mul(wvpMat, iPosition);
	vColor = srgb_to_linear(iColor.bgra) * srgb_to_linear(diffuseColor);
	vDepth = oPosition.z;
}

// -------------------------------------------

void untextured_fragment(
	uniform float3 fogColour,
	uniform float4 fogParams,

	in float4 vColor : COLOR0,
	in float vDepth : TEXCOORD1,

	out float4 oColor : SV_TARGET
#ifdef LOGDEPTH_ENABLE	
	, out float oDepth : SV_DEPTH
#endif
	)
{
	oColor = vColor;

	float fogValue = saturate((vDepth - fogParams.y) * fogParams.w);
	oColor.xyz = lerp(oColor.xyz, srgb_to_linear(fogColour), fogValue);
	oColor.xyz = linear_to_srgb(oColor.xyz);

#ifdef LOGDEPTH_ENABLE	
	const float C = 0.1;
	const float far = 1e+09;
	const float offset = 1.0;
	oDepth = log(C * vDepth + offset) / log(C * far + offset);
#endif
}
