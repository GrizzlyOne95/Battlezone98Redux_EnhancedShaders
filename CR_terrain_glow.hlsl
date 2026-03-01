float3 srgb_to_linear(float3 c) { return pow(max(c, 0.0), 2.2); }
float4 srgb_to_linear(float4 c) { return float4(pow(max(c.xyz, 0.0), 2.2), c.w); }
float3 linear_to_srgb(float3 c) { return pow(max(c, 0.0), 1.0 / 2.2); }
float4 linear_to_srgb(float4 c) { return float4(pow(max(c.xyz, 0.0), 1.0 / 2.2), c.w); }

void terrain_vertex(
	uniform float4x4 wvpMat,
	uniform float4 diffuseColor,

	in float4 iPosition : POSITION,
	in float4 iColor : COLOR0,
	in uint2 iBlendIndices : BLENDINDICES,
	in float heightOffset : TEXCOORD1,

	out float4 vColor : COLOR0,
	out float2 vTexCoord : TEXCOORD0,
	out float vDepth : TEXCOORD1,

	out float4 oPosition : POSITION
)
{
	iPosition.y = heightOffset;

	oPosition = mul(wvpMat, iPosition);
	vColor = srgb_to_linear(iColor) * srgb_to_linear(diffuseColor);
	// Sample atlas texels at center to avoid orientation-dependent half-texel distortion.
	vTexCoord = (float2(iBlendIndices) + 0.5) / 160.0;
	vDepth = oPosition.z;
}

// -------------------------------------------

void terrain_fragment(
	uniform sampler2D diffuseMap : register(s0),

	uniform float4 fogColour,
	uniform float4 fogParams,

	in float4 vColor : COLOR,
	in float2 vTexCoord : TEXCOORD0,
	in float vDepth : TEXCOORD1,

	out float4 oColor : COLOR
#ifdef LOGDEPTH_ENABLE	
	, out float oDepth : DEPTH
#endif
)
{
	// diffuse texture
	float3 diffuseTex = srgb_to_linear(tex2D(diffuseMap, vTexCoord).xyz);
	oColor.xyz = diffuseTex.xyz * vColor.rgb;

	// fog
	float fogValue = saturate((vDepth - fogParams.y) * fogParams.w);
	oColor.xyz = lerp(oColor.xyz, srgb_to_linear(fogColour.xyz), fogValue);
	oColor.xyz = linear_to_srgb(oColor.xyz);

	// output alpha
	oColor.a = vColor.a;

#ifdef LOGDEPTH_ENABLE
	// logarithmic depth
	const float C = 0.1;
	const float offset = 1.0;
	const float kInvLogDepthDenom = 0.054286812;
	oDepth = log(C * vDepth + offset) * kInvLogDepthDenom;
#endif
}
