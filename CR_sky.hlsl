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

float noise12(float2 p)
{
	float2 i = floor(p);
	float2 f = frac(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + float2(1.0, 0.0));
	float c = hash12(i + float2(0.0, 1.0));
	float d = hash12(i + float2(1.0, 1.0));
	return lerp(lerp(a, b, f.x), lerp(c, d, f.x), f.y);
}

float fbm3(float2 p)
{
	float v = 0.0;
	v += 0.5714286 * noise12(p);
	p = p * 2.03 + float2(17.1, 9.2);
	v += 0.2857143 * noise12(p);
	p = p * 2.01 + float2(11.3, 13.7);
	v += 0.1428571 * noise12(p);
	return v;
}

float2 rotate2d(float2 p, float angle)
{
	float s = sin(angle);
	float c = cos(angle);
	return float2(c * p.x - s * p.y, s * p.x + c * p.y);
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
	uniform float procStarStrength,
	uniform float procStarDensity,
	uniform float2 procStarDrift,
	uniform float nebulaStrength,
	uniform float nebulaScale,
	uniform float2 nebulaDrift,
	uniform float horizonStrength,
	uniform float sunDiskStrength,
	uniform float sunDiskRadius,

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

	float procStarDensityValue = max(procStarDensity, 1.0);
	float2 procStarUv = vTexCoord + procStarDrift * (skyTime * 0.01);
	float2 procStarCellUv = procStarUv * procStarDensityValue;
	float2 procStarCell = floor(procStarCellUv);
	float2 procStarLocal = frac(procStarCellUv) - 0.5;
	float procStarHashA = hash12(procStarCell);
	float procStarHashB = hash12(procStarCell + float2(13.7, 5.1));
	float procStarSpawn = smoothstep(0.988, 0.9995, procStarHashA);
	float procStarCore = saturate(1.0 - dot(procStarLocal, procStarLocal) * lerp(18.0, 34.0, procStarHashB));
	float procStarPulse = 0.72 + 0.28 * sin(skyTime * (1.2 + procStarHashB * 3.6) + procStarHashA * 6.2831853);
	float procStars = procStarSpawn * procStarCore * procStarPulse * max(procStarStrength, 0.0);
	float3 procStarColor = lerp(float3(0.72, 0.80, 1.0), float3(1.0, 0.93, 0.84), procStarHashB);
	color += procStarColor * procStars;
	alpha = saturate(alpha + procStars * 0.30);

	float nebulaStrengthValue = max(nebulaStrength, 0.0);
	float nebulaScaleValue = max(nebulaScale, 0.01);
	float2 nebulaUv = rotate2d(uvN, skyTime * nebulaDrift.x * 0.03);
	nebulaUv = nebulaUv * nebulaScaleValue + nebulaDrift * (skyTime * 0.025);
	float nebulaBase = fbm3(nebulaUv + float2(2.7, -1.9));
	float nebulaDetail = fbm3(nebulaUv * 1.9 + float2(-4.3, 7.1));
	float nebulaRidge = 1.0 - abs(nebulaDetail * 2.0 - 1.0);
	float nebulaMask = smoothstep(0.48, 0.82, nebulaBase * 0.72 + nebulaRidge * 0.28);
	float nebulaTintMix = fbm3(nebulaUv * 1.3 + float2(5.4, 1.2));
	float3 nebulaTintA = lerp(float3(0.07, 0.12, 0.28), skyTint, 0.55);
	float3 nebulaTintB = lerp(float3(0.34, 0.12, 0.10), skyTint.bgr, 0.25);
	float3 nebulaColor = lerp(nebulaTintA, nebulaTintB, nebulaTintMix);
	float nebulaFalloff = saturate(1.0 - dot(uvN * 0.55, uvN * 0.55));
	color += nebulaColor * nebulaMask * nebulaStrengthValue * (0.45 + nebulaFalloff * 0.55);
	alpha = saturate(alpha + nebulaMask * nebulaStrengthValue * 0.18);

	float horizonGlow = exp(-abs(uvN.y) * 7.5) * max(horizonStrength, 0.0);
	float sunScatter = saturate(1.0 - length(sunOffset) * 1.6);
	float3 horizonColor = lerp(float3(0.05, 0.07, 0.12), skyTint, 0.35);
	color += horizonColor * horizonGlow * (0.65 + sunScatter * 0.35);

	float sunPulse = 1.0 + sin(skyTime * sunPulseSpeed) * sunPulseStrength;
	float sunDiskMask = 1.0 - smoothstep(max(sunDiskRadius, 1e-3), max(sunDiskRadius, 1e-3) + max(sunCoronaSoftness * 0.45, 1e-3), sunRadius);
	float3 sunDiskColor = lerp(float3(1.0, 0.94, 0.82), skyTint, 0.22);
	color += sunDiskColor * sunDiskMask * max(sunDiskStrength, 0.0);
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
