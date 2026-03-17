void textured_vertex(
	uniform float4x4 wvpMat,

	in float4 iPosition : POSITION,
	in float2 iTexCoord : TEXCOORD0,

	out float2 vTexCoord : TEXCOORD0,
	out float vDepth : TEXCOORD1,

	out float4 oPosition : SV_POSITION
)
{
	oPosition = mul(wvpMat, iPosition);
	vTexCoord = iTexCoord;
	vDepth = oPosition.z;
}

// -------------------------------------------

void textured_fragment(
	uniform Texture2D diffuseMap : register(t0),
	uniform SamplerState diffuseSam : register(s0),

	uniform float4 diffuseColor,

	uniform float3 fogColour,
	uniform float4 fogParams,

	in float2 vTexCoord : TEXCOORD0,
	in float vDepth : TEXCOORD1,

	out float4 oColor : SV_TARGET
#ifdef LOGDEPTH_ENABLE
	, out float oDepth : SV_DEPTH
#endif
)
{
	float4 diffuseTex = diffuseMap.Sample(diffuseSam, vTexCoord);
	oColor = diffuseTex * diffuseColor;

	float fogValue = saturate((vDepth - fogParams.y) * fogParams.w);
	oColor.xyz = lerp(oColor.xyz, fogColour, fogValue);
	
#ifdef LOGDEPTH_ENABLE
	const float C = 0.1;
	const float far = 1e+09;
	const float offset = 1.0;
	oDepth = log(C * vDepth + offset) / log(C * far + offset);
#endif
}
