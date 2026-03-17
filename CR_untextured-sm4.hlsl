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
	vColor = iColor.bgra * diffuseColor;
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
	oColor.xyz = lerp(oColor.xyz, fogColour, fogValue);

#ifdef LOGDEPTH_ENABLE	
	const float C = 0.1;
	const float far = 1e+09;
	const float offset = 1.0;
	oDepth = log(C * vDepth + offset) / log(C * far + offset);
#endif
}
