void main(
	uniform float4x4 wvpMat,
	in float4 iPos: POSITION,
	in float2 iTexCoord : TEXCOORD0,
	out float2 oTexCoord : TEXCOORD0,
	out float4 oPosition : SV_POSITION
	){
   oPosition = mul(wvpMat, iPos);
   oTexCoord = iTexCoord;
}

