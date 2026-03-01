void uitexmat_vertex(
	uniform float4x4 wvpMat,
	uniform float4x4 texMat,

	in float4 iPosition : POSITION,
	in float4 iColor : COLOR0,
	in float4 iTexCoord : TEXCOORD0,

	out float4 vColor : COLOR0,
	out float2 vTexCoord : TEXCOORD0,

	out float4 oPosition : SV_POSITION
	)
{
	oPosition = mul(wvpMat, iPosition);
	vColor = iColor.bgra;
	vTexCoord = mul(texMat, iTexCoord).xy;
}

// -------------------------------------------

void uitexmat_fragment(
	uniform Texture2D diffuseMap : register(t0),
	uniform SamplerState diffuseSam : register(s0),

	in float4 vColor : COLOR0,
	in float2 vTexCoord : TEXCOORD0,

	out float4 oColor : SV_TARGET
)
{
	float4 diffuseTex = diffuseMap.Sample(diffuseSam, vTexCoord);
	oColor = diffuseTex * vColor;
}
