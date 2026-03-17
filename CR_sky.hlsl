void sky_vertex(
	uniform float4x4 wvpMat,

	in float4 iPosition : POSITION,
	in float4 iColor : COLOR0,
	in float2 iTexCoord : TEXCOORD0,

	out float4 vColor : COLOR0,
	out float2 vTexCoord : TEXCOORD0,
	out float vDepth : TEXCOORD1,

	out float4 oPosition : POSITION
)
{
	oPosition = mul(wvpMat, iPosition);
	vColor = iColor;
	vTexCoord = iTexCoord;
	vDepth = oPosition.z;
}

// -------------------------------------------

void sky_fragment(
	uniform sampler2D diffuseMap : register(s0),

	in float4 vColor : COLOR0,
	in float2 vTexCoord : TEXCOORD0,
	in float vDepth : TEXCOORD1,

	out float4 oColor : COLOR
#ifdef LOGDEPTH_ENABLE
	, out float oDepth : DEPTH
#endif
)
{
	float4 diffuseTex = tex2D(diffuseMap, vTexCoord);
	oColor = diffuseTex * vColor;
	
#ifdef LOGDEPTH_ENABLE
	const float C = 0.1;
	const float far = 1e+09;
	const float offset = 1.0;
	oDepth = log(C * vDepth + offset) / log(C * far + offset);
#endif
}
