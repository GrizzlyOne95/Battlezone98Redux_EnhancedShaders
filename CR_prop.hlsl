#if !defined(VERTEX_TANGENTS)
float3x3 cotangent_frame(float3 N, float3 p, float2 uv)
{
	float3 dp1 = ddx(p);
	float3 dp2 = ddy(p);
	float2 duv1 = ddx(uv);
	float2 duv2 = ddy(uv);
	float3 dp2perp = cross(N, dp2);
	float3 dp1perp = cross(dp1, N);
	float3 T = dp2perp * duv1.x + dp1perp * duv2.x;
	float3 B = dp2perp * duv1.y + dp1perp * duv2.y;
	float invmax = rsqrt(max(dot(T, T), dot(B, B)) + 1e-30);
	return float3x3(T * invmax, B * invmax, N);
}
#endif

float2 animate_uv(
	float2 uv,
	float2 uvScale,
	float2 uvPan,
	float2 uvScroll,
	float uvRotateSpeed,
	float propTime)
{
	float2 centered = uv * uvScale + uvPan + uvScroll * propTime - float2(0.5, 0.5);
	float angle = uvRotateSpeed * propTime;
	float s = sin(angle);
	float c = cos(angle);
	float2 rotated = float2(centered.x * c - centered.y * s, centered.x * s + centered.y * c);
	return rotated + float2(0.5, 0.5);
}

float hash12(float2 p)
{
	return frac(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

float smooth_rand_1d(float x, float seed)
{
	float i = floor(x);
	float f = frac(x);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash12(float2(i, seed));
	float b = hash12(float2(i + 1.0, seed));
	return lerp(a, b, f);
}

float emissive_anim_factor(
	float2 uv,
	float t,
	float mask,
	float emissiveAnimStrength,
	float emissiveAnimScale)
{
	float strength = saturate(emissiveAnimStrength) * saturate(mask);
	float scale = max(emissiveAnimScale, 0.1);
	float2 gridUv = uv * scale * 2.2;
	float2 cell = floor(gridUv);
	float2 local = frac(gridUv) - 0.5;
	float cellSeed = hash12(cell + float2(19.1, 73.7));
	float cellPhase = hash12(cell + float2(11.7, 5.3)) * 6.2831853;
	float cellSpeed = lerp(0.30, 1.35, hash12(cell + float2(37.2, 29.8)));
	float slowPulse = 0.5 + 0.5 * sin(t * cellSpeed + cellPhase);
	float drift = smooth_rand_1d(t * (0.24 + cellSpeed * 0.18) + cellPhase, 91.0 + cellSeed * 211.0);
	float flicker = smooth_rand_1d(t * (0.75 + cellSpeed * 0.55) + cellPhase * 1.7, 173.0 + cellSeed * 307.0);
	float cellCore = smoothstep(0.72, 0.06, length(local));
	float mod = slowPulse * 0.58 + drift * 0.27 + flicker * 0.15;
	float anim = lerp(0.42, 1.36, mod) * lerp(0.88, 1.10, cellCore);
	anim = saturate(anim);
	return lerp(1.0, anim, strength);
}

float3 subtle_tonemap(float3 c)
{
	float3 t = (c * (1.0 + c / 1.8)) / (1.0 + c);
	return lerp(c, t, 0.10);
}

float3 srgb_to_linear(float3 c) { return pow(max(c, 0.0), 2.2); }
float4 srgb_to_linear(float4 c) { return float4(pow(max(c.xyz, 0.0), 2.2), c.w); }
float3 linear_to_srgb(float3 c) { return pow(max(c, 0.0), 1.0 / 2.2); }
float4 linear_to_srgb(float4 c) { return float4(pow(max(c.xyz, 0.0), 1.0 / 2.2), c.w); }

float D_GGX(float NdotH, float roughness) {
    float a = roughness * roughness;
    float a2 = a * a;
    float NdotH2 = NdotH * NdotH;
    float d = NdotH2 * (a2 - 1.0) + 1.0;
    return a2 / (3.14159265 * d * d);
}

float G_SchlickGGX(float NdotV, float NdotL, float roughness) {
    float r = roughness + 1.0;
    float k = (r * r) / 8.0;
    float gv = NdotV / (NdotV * (1.0 - k) + k);
    float gl = NdotL / (NdotL * (1.0 - k) + k);
    return gv * gl;
}

float3 F_Schlick(float cosTheta, float3 F0) {
    return F0 + (1.0 - F0) * pow(1.0 - saturate(cosTheta), 5.0);
}

void prop_vertex(
	uniform float4x4 wvpMat,
	uniform float4x4 worldViewMat,

	in float4 iPosition : POSITION,
	in float3 iNormal : NORMAL,
	in float2 iTexCoord : TEXCOORD0,
#if defined(VERTEX_TANGENTS)
	in float3 iTangent : TANGENT,
#endif

	out float2 vTexCoord : TEXCOORD0,
	out float3 vViewNormal : TEXCOORD1,
#if defined(VERTEX_TANGENTS)
	out float3 vViewTangent : TEXCOORD2,
#endif
	out float3 vViewPosition : TEXCOORD3,
	out float vDepth : TEXCOORD4,
	out float4 oPosition : POSITION
)
{
	oPosition = mul(wvpMat, iPosition);
	vTexCoord = iTexCoord;
	vViewPosition = mul(worldViewMat, float4(iPosition.xyz, 1.0)).xyz;
	vViewNormal = normalize(mul(worldViewMat, float4(iNormal.xyz, 0.0)).xyz);
#if defined(VERTEX_TANGENTS)
	vViewTangent = normalize(mul(worldViewMat, float4(iTangent.xyz, 0.0)).xyz);
#endif
	vDepth = oPosition.z;
}

void prop_fragment(
	uniform sampler2D diffuseMap : register(s0),
	uniform sampler2D normalMap : register(s1),
	uniform sampler2D specularMap : register(s2),
	uniform sampler2D emissiveMap : register(s3),

	uniform float4 diffuseColor,
	uniform float3 fogColour,
	uniform float4 fogParams,
	uniform float4 sceneAmbient,
	uniform float materialShininess,

	uniform float4 lightDiffuse[MAX_LIGHTS],
	uniform float4 lightSpecular[MAX_LIGHTS],
	uniform float4 lightPosition[MAX_LIGHTS],
	uniform float4 lightAttenuation[MAX_LIGHTS],
	uniform float4 spotLightParams[MAX_LIGHTS],
	uniform float4 lightDirection[MAX_LIGHTS],
	uniform float lightCount,

	uniform float propTime,
	uniform float2 uvScale,
	uniform float2 uvPan,
	uniform float2 uvScroll,
	uniform float uvRotateSpeed,
	uniform float alphaCutoff,
	uniform float alphaSoftness,
	uniform float alphaMultiplier,
	uniform float normalStrength,
	uniform float specularStrength,
	uniform float glossStrength,
	uniform float emissiveStrength,
	uniform float emissiveAnimStrength,
	uniform float emissiveAnimSpeed,
	uniform float emissiveAnimScale,

	in float2 vTexCoord : TEXCOORD0,
	in float3 vViewNormal : TEXCOORD1,
#if defined(VERTEX_TANGENTS)
	in float3 vViewTangent : TEXCOORD2,
#endif
	in float3 vViewPosition : TEXCOORD3,
	in float vDepth : TEXCOORD4,

	out float4 oColor : COLOR
#ifdef LOGDEPTH_ENABLE
	, out float oDepth : DEPTH
#endif
)
{
	float2 uv = animate_uv(vTexCoord, uvScale, uvPan, uvScroll, uvRotateSpeed, propTime);
	float4 dTexSample = tex2D(diffuseMap, uv);
	float4 dTex = float4(srgb_to_linear(dTexSample.xyz) * srgb_to_linear(diffuseColor.xyz), dTexSample.a * diffuseColor.a);
	float alpha = saturate(dTex.a * alphaMultiplier);
	clip(alpha - alphaCutoff);
	alpha *= saturate((alpha - alphaCutoff) / max(alphaSoftness, 1e-3));

	float3 baseNormal = normalize(vViewNormal);
#if defined(VERTEX_TANGENTS)
	float3 binormal = normalize(cross(vViewTangent, baseNormal));
	float3x3 tbn = float3x3(vViewTangent, binormal, baseNormal);
#else
	float3x3 tbn = cotangent_frame(baseNormal, vViewPosition, uv);
#endif

	float3 nTex = tex2D(normalMap, uv).xyz * 2.0 - 1.0;
	nTex.xy *= normalStrength;
	nTex.z = sqrt(saturate(1.0 - dot(nTex.xy, nTex.xy)));
	float3 viewNormal = normalize(mul(nTex, tbn));
	float3 viewDir = normalize(-vViewPosition);

	float3 lightAccum = srgb_to_linear(sceneAmbient.xyz);
	float3 specAccum = float3(0, 0, 0);
	float3 specTex = srgb_to_linear(tex2D(specularMap, uv).xyz);
	float glossTex = tex2D(specularMap, uv).a;
	float3 emissiveTex = srgb_to_linear(tex2D(emissiveMap, uv).xyz);
	float emissiveMask = saturate(dot(emissiveTex, float3(0.299, 0.587, 0.114)) * 3.2);
	float emissiveAnim = emissive_anim_factor(uv, propTime * emissiveAnimSpeed, emissiveMask, emissiveAnimStrength, max(emissiveAnimScale, 0.1));
	emissiveTex *= emissiveAnim;

	float roughness = saturate(sqrt(2.0 / (max(materialShininess * lerp(0.5, 2.5, glossTex * glossStrength), 1.0) + 2.0)));
	float3 f0 = float3(0.04, 0.04, 0.04);

	for (int i = 0; i < MAX_LIGHTS; ++i)
	{
		if (i >= int(lightCount))
			break;

		float3 pixelToLight = lightPosition[i].xyz - (vViewPosition * lightPosition[i].w);
		float d = length(pixelToLight);
		pixelToLight /= max(d, 1e-4);
		float attenuation = saturate(1.0 /
			(lightAttenuation[i].y + d * (lightAttenuation[i].z + d * lightAttenuation[i].w)));
		attenuation *= pow(clamp(
			(dot(pixelToLight, -lightDirection[i].xyz) - spotLightParams[i].y) /
			(spotLightParams[i].x - spotLightParams[i].y), 1e-30, 1.0), spotLightParams[i].z);

		float NdotL = saturate(dot(viewNormal, pixelToLight));
		lightAccum += srgb_to_linear(lightDiffuse[i].xyz) * attenuation * NdotL;

		float3 halfVec = normalize(pixelToLight + viewDir);
		float NdotH = saturate(dot(viewNormal, halfVec));
		float NdotV = saturate(dot(viewNormal, viewDir));

		float D = D_GGX(NdotH, roughness);
		float G = G_SchlickGGX(NdotV, NdotL, roughness);
		float3 F = F_Schlick(saturate(dot(halfVec, viewDir)), f0);
		
		float3 specularTerm = (D * G * F) / max(4.0 * NdotL * NdotV, 0.001);
		specAccum += srgb_to_linear(lightSpecular[i].xyz) * attenuation * specularTerm * max(NdotL, 0.0);
	}

	oColor.xyz = dTex.xyz * lightAccum;
	oColor.xyz += specAccum * specTex * specularStrength;
	oColor.xyz += emissiveTex * emissiveStrength;

    oColor.xyz = min(oColor.xyz, 3.0);
    float3 exposedColor = oColor.xyz * 1.20;
    oColor.xyz = lerp(exposedColor, subtle_tonemap(exposedColor), 0.55);

	float fogValue = saturate((vDepth - fogParams.y) * fogParams.w);
	oColor.xyz = lerp(oColor.xyz, srgb_to_linear(fogColour.xyz), fogValue);
	
	oColor.xyz = linear_to_srgb(oColor.xyz);
	oColor.a = alpha;

#ifdef LOGDEPTH_ENABLE
	const float C = 0.1;
	const float offset = 1.0;
	const float kInvLogDepthDenom = 0.054286812;
	oDepth = log(C * vDepth + offset) * kInvLogDepthDenom;
#endif
}
