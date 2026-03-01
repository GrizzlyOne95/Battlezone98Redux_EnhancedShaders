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

float hash12(float2 p)
{
	return frac(sin(dot(p, float2(127.1, 311.7))) * 43758.5453123);
}

void sky_fragment(
	uniform sampler2D diffuseMap : register(s0),
	uniform float skyExposure,
	uniform float skyContrast,
	uniform float skySaturation,
	uniform float skyBlackPoint,
	uniform float skyVignette,
	uniform float skyTime,
	uniform float starThreshold,
	uniform float starBloomStrength,
	uniform float twinkleStrength,
	uniform float twinkleSpeed,
	uniform float twinkleScale,
	uniform float twinkleMin,
	uniform float2 meteorScroll,
	uniform float meteorStrength,
	uniform float meteorThreshold,
	uniform float meteorSoftness,
	uniform float sunPulseStrength,
	uniform float sunPulseSpeed,
	uniform float sunDistortStrength,
	uniform float sunDistortSpeed,
	uniform float sunDistortScale,
	uniform float sunCoronaStrength,
	uniform float sunCoronaRadius,
	uniform float sunCoronaSoftness,
	uniform float2 sunCenter,
	uniform float3 skyTint,

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
	float ripplePhase = skyTime * sunDistortSpeed + sunRadius * max(sunDistortScale, 1e-3) * 6.2831853;
	float ripple = sin(ripplePhase) * sunDistortStrength * 0.01;
	float2 rippleDir = sunRadius > 1e-4 ? (sunOffset / sunRadius) : float2(0.0, 0.0);
	float2 baseUv = vTexCoord + rippleDir * ripple;
	float4 diffuseTex = tex2D(diffuseMap, baseUv);
	float3 color = diffuseTex.xyz * vColor.xyz;
	float alpha = diffuseTex.a * vColor.a;
	float luma = dot(color, float3(0.299, 0.587, 0.114));
	float3 gray = luma.xxx;
	color = lerp(gray, color, max(skySaturation, 0.0));
	color = (color - 0.5) * skyContrast + 0.5;
	float invBlack = rcp(max(1.0 - skyBlackPoint, 1e-3));
	color = saturate((color - skyBlackPoint.xxx) * invBlack);
	float2 uvN = vTexCoord * 2.0 - 1.0;
	float vignette = saturate(1.0 - dot(uvN, uvN) * 0.35);
	color *= lerp(1.0, vignette, saturate(skyVignette));
	float starMask = saturate((luma - starThreshold) * 4.0);
	float2 twinkleCell = floor(vTexCoord * max(twinkleScale, 1.0));
	float twinkleHashA = hash12(twinkleCell);
	float twinkleHashB = hash12(twinkleCell + float2(19.19, 73.73));
	float twinkleHashC = hash12(twinkleCell + float2(47.17, 11.83));
	float twinkleHashD = hash12(twinkleCell + float2(83.21, 14.59));
	float isTwinkler = smoothstep(0.4, 0.6, twinkleHashD);
	float twinklePhase = twinkleHashA * 6.2831853;
	float twinkleSpeedJitter = lerp(0.5, 2.0, twinkleHashB);
	float twinkleWaveA = sin(skyTime * twinkleSpeed * twinkleSpeedJitter + twinklePhase);
	float twinkleWaveB = sin(skyTime * twinkleSpeed * (1.35 + twinkleHashC * 0.75) + (twinkleHashB + 0.37) * 6.2831853);
	float twinkleWave = (twinkleWaveA * 0.72 + twinkleWaveB * 0.28) * isTwinkler;
	float twinkleFactor = 1.0 + starMask * twinkleStrength * twinkleWave;
	twinkleFactor = max(twinkleFactor, twinkleMin);
	color *= twinkleFactor;
	alpha *= saturate(lerp(1.0, twinkleFactor, starMask));
	float2 meteorUv = frac(vTexCoord + meteorScroll * skyTime);
	float3 meteorTex = tex2D(diffuseMap, meteorUv).xyz * vColor.xyz;
	float meteorLuma = dot(meteorTex, float3(0.299, 0.587, 0.114));
	float meteorMask = smoothstep(meteorThreshold, meteorThreshold + max(meteorSoftness, 1e-3), meteorLuma);
	color += meteorTex * meteorMask * meteorStrength;
	alpha = saturate(alpha + meteorMask * meteorStrength * 0.25);
	color += color * starMask * starBloomStrength;
	float sunPulse = 1.0 + sin(skyTime * sunPulseSpeed) * sunPulseStrength;
	float coronaMask = 1.0 - smoothstep(sunCoronaRadius, sunCoronaRadius + max(sunCoronaSoftness, 1e-3), sunRadius);
	color += color * coronaMask * sunCoronaStrength;
	color *= sunPulse;
	color *= skyExposure * skyTint;
	oColor = float4(color, alpha);
	
#ifdef LOGDEPTH_ENABLE
	const float C = 0.1;
	const float offset = 1.0;
	const float kInvLogDepthDenom = 0.054286812;
	oDepth = log(C * vDepth + offset) * kInvLogDepthDenom;
#endif
}
