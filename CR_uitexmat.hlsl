void uitexmat_vertex(
	uniform float4x4 wvpMat,
	uniform float4x4 texMat,

	in float4 iPosition : POSITION,
	in float4 iColor : COLOR0,
	in float4 iTexCoord : TEXCOORD0,

	out float4 vColor : COLOR0,
	out float2 vTexCoord : TEXCOORD0,

	out float4 oPosition : POSITION
	)
{
	oPosition = mul(wvpMat, iPosition);
	vColor = iColor;
	vTexCoord = mul(texMat, iTexCoord).xy;
}

// -------------------------------------------

void uitexmat_fragment(
	uniform sampler2D diffuseMap : register(s0),

	in float4 vColor : COLOR0,
	in float2 vTexCoord : TEXCOORD0,

	out float4 oColor : COLOR
)
{
	float4 diffuseTex = tex2D(diffuseMap, vTexCoord);
	oColor = diffuseTex * vColor;
}
