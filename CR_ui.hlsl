void ui_vertex(
	uniform float4x4 wvpMat,

	in float4 iPosition : POSITION,
	in float4 iColor : COLOR0,
	in float2 iTexCoord : TEXCOORD0,

	out float4 vColor : COLOR0,
	out float2 vTexCoord : TEXCOORD0,

	out float4 oPosition : POSITION
	)
{
	oPosition = mul(wvpMat, iPosition);
	vColor = iColor;
	vTexCoord = iTexCoord;
}

// -------------------------------------------

void ui_fragment(
	uniform sampler2D diffuseMap : register(s0),

	in float4 vColor : COLOR0,
	in float2 vTexCoord : TEXCOORD0,

	out float4 oColor : COLOR
)
{
	float4 diffuseTex = tex2D(diffuseMap, vTexCoord);
	oColor = diffuseTex * vColor;
}
