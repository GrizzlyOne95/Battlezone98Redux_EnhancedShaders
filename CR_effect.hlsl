float3 srgb_to_linear(float3 c) { return pow(max(c, 0.0), 2.2); }
float4 srgb_to_linear(float4 c) { return float4(pow(max(c.xyz, 0.0), 2.2), c.w); }
float3 linear_to_srgb(float3 c) { return pow(max(c, 0.0), 1.0 / 2.2); }
float4 linear_to_srgb(float4 c) { return float4(pow(max(c.xyz, 0.0), 1.0 / 2.2), c.w); }

void effect_vertex(
	uniform float4x4 wvpMat,
	uniform float4 diffuseColor,

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
	vColor = srgb_to_linear(iColor) * srgb_to_linear(diffuseColor);
	vTexCoord = iTexCoord;
	vDepth = oPosition.z;
}

// -------------------------------------------

void effect_fragment(
	uniform sampler2D diffuseMap : register(s0),

	uniform half3 fogColour,
	uniform float4 fogParams,
	uniform float effectTime,
	uniform float sunPulseStrength,
	uniform float sunPulseSpeed,
	uniform float sunDistortStrength,
	uniform float sunDistortSpeed,
	uniform float sunDistortScale,
	uniform float sunCoronaStrength,
	uniform float sunCoronaRadius,
	uniform float sunCoronaSoftness,
	uniform float2 sunCenter,
	uniform float2 effectUVScroll,
	uniform float2 effectLayer2Scroll,
	uniform float effectLayer2Blend,
	uniform float effectAlphaSoftness,

	in float4 vColor : COLOR0,
	in float2 vTexCoord : TEXCOORD0,
	in float vDepth : TEXCOORD1,

	out float4 oColor : COLOR
#ifdef LOGDEPTH_ENABLE
	, out float oDepth : DEPTH
#endif
)
{
	float2 sunOffset = vTexCoord - sunCenter;
	float sunRadius = length(sunOffset);
	float ripplePhase = effectTime * sunDistortSpeed + sunRadius * max(sunDistortScale, 1e-3) * 6.2831853;
	float ripple = sin(ripplePhase) * sunDistortStrength * 0.01;
	float2 rippleDir = sunRadius > 1e-4 ? (sunOffset / sunRadius) : float2(0.0, 0.0);
	float2 animatedUv = vTexCoord + rippleDir * ripple;
	float2 scrollUv = animatedUv + effectUVScroll * effectTime;
	half4 diffuseTex = srgb_to_linear(tex2D(diffuseMap, scrollUv));
	float2 layer2Uv = animatedUv + effectLayer2Scroll * effectTime;
	half4 layer2Tex = srgb_to_linear(tex2D(diffuseMap, layer2Uv));
	diffuseTex = lerp(diffuseTex, layer2Tex, saturate(effectLayer2Blend));
	diffuseTex.a = saturate(pow(saturate(diffuseTex.a), max(effectAlphaSoftness, 0.05)));
	oColor = diffuseTex * vColor;
	float sunPulse = 1.0 + sin(effectTime * sunPulseSpeed) * sunPulseStrength;
	float coronaMask = 1.0 - smoothstep(sunCoronaRadius, sunCoronaRadius + max(sunCoronaSoftness, 1e-3), sunRadius);
	oColor.xyz += oColor.xyz * coronaMask * sunCoronaStrength;
	oColor.xyz *= sunPulse;

	float fogValue = saturate((vDepth - fogParams.y) * fogParams.w);
	oColor.xyz = lerp(oColor.xyz, srgb_to_linear(fogColour), fogValue);
	oColor.xyz = linear_to_srgb(oColor.xyz);
	
#ifdef LOGDEPTH_ENABLE
	const float C = 0.1;
	const float offset = 1.0;
	const float kInvLogDepthDenom = 0.054286812;
	oDepth = log(C * vDepth + offset) * kInvLogDepthDenom;
#endif
}
