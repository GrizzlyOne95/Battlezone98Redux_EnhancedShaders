// CR_base.hlsl - DX9 (SM3) PBR shader for BZ98R
// Physically-based: GGX specular, linear-space lighting, energy-conserving diffuse,
// Fresnel-based metal/dielectric split, hemisphere ambient, IBL approx, AO, PCSS shadows.

// ============================================================
// Shadow Filtering
// ============================================================
#if defined(SHADOWRECEIVER) 
float PCF_Filter(in sampler2D map,
					in float4 uv,
					in float2 invMapSize,
					in float receiverDepth)
{
	uv /= uv.w;
	uv.z = min(uv.z, 1.0);
	float2 texel = invMapSize;
	
	// PCSS-Lite: contact hardening based on blocker distance
    float blockerDepth = tex2D(map, uv.xy).x;
    float penumbra = saturate(uv.z - blockerDepth);
    float filterScale = 1.0 + penumbra * 80.0; 
    texel *= filterScale;

	float compareDepth = uv.z - (0.0012 + max(texel.x, texel.y) * 1.4);
	
#if PCF_SIZE == 3
#if defined(HIGH_SHADOW_QUALITY)
	float2 poisson[12] = {
		float2(-0.326, -0.406), float2(-0.840, -0.074), float2(-0.696, 0.457), float2(-0.203, 0.621),
		float2(0.962, -0.195), float2(0.473, -0.480), float2(0.519, 0.767), float2(0.185, -0.893),
		float2(0.507, 0.064), float2(0.896, 0.412), float2(-0.322, -0.933), float2(-0.792, -0.598)
	};
	float sum = 0.0;
	[unroll] for (int i = 0; i < 12; ++i)
	{
		float2 offset = poisson[i] * texel * 1.35;
		sum += step(compareDepth, tex2D(map, uv.xy + offset).x);
	}
	return sum / 12.0;
#else
	float2 pixel = uv.xy / invMapSize - float2(float(PCF_SIZE-1)*0.5, float(PCF_SIZE-1)*0.5);
	float2 c = floor(pixel);
	float2 f = frac(pixel);

	float kernel[PCF_SIZE*PCF_SIZE];
	for (int y = 0; y < PCF_SIZE; ++y)
		for (int x = 0; x < PCF_SIZE; ++x)
		{
			int i = y * PCF_SIZE + x;
			kernel[i] = step(uv.z, tex2D(map, (c + float2(x, y)) * invMapSize).x);
		}

	float4 sum = float4(0.0, 0.0, 0.0, 0.0);
	for (int y = 0; y < PCF_SIZE-1; ++y)
		for (int x = 0; x < PCF_SIZE-1; ++x)
		{
			int i = y * PCF_SIZE + x;
			sum += float4(kernel[i], kernel[i+1], kernel[i+PCF_SIZE], kernel[i+PCF_SIZE+1]);
		}

	return lerp(lerp(sum.x, sum.y, f.x), lerp(sum.z, sum.w, f.x), f.y) / float((PCF_SIZE-1)*(PCF_SIZE-1));
#endif
#elif PCF_SIZE == 2
	float2 pixel = uv.xy / invMapSize - float2(0.5, 0.5);
	float2 c = floor(pixel);
	float2 f = frac(pixel);
	float k00 = step(compareDepth, tex2D(map, (c + float2(0.0, 0.0)) * invMapSize).x);
	float k10 = step(compareDepth, tex2D(map, (c + float2(1.0, 0.0)) * invMapSize).x);
	float k01 = step(compareDepth, tex2D(map, (c + float2(0.0, 1.0)) * invMapSize).x);
	float k11 = step(compareDepth, tex2D(map, (c + float2(1.0, 1.0)) * invMapSize).x);
	return lerp(lerp(k00, k10, f.x), lerp(k01, k11, f.x), f.y);
#else
	return step(compareDepth, tex2D(map, uv.xy).x);
#endif
}
#endif

// ============================================================
// Normal Map Helpers
// ============================================================
#if defined(NORMALMAP_ENABLED) && !defined(VERTEX_TANGENTS)
// Cotangent frame derivation (no vertex tangents needed)
// http://www.thetenthplanet.de/archives/1180
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
	T *= invmax;
	B *= invmax;
	return float3x3(T, B, N);
}
#endif

// ============================================================
// Screen-space dithering (Bayer 4x4) for alpha transparency
// ============================================================
float GetDither(float2 pos)
{
	const float4x4 bayer = float4x4(
		0.0/16.0, 12.0/16.0,  3.0/16.0, 15.0/16.0,
		8.0/16.0,  4.0/16.0, 11.0/16.0,  7.0/16.0,
		2.0/16.0, 14.0/16.0,  1.0/16.0, 13.0/16.0,
		10.0/16.0, 6.0/16.0,  9.0/16.0,  5.0/16.0
	);
	int x = int(fmod(pos.x, 4.0));
	int y = int(fmod(pos.y, 4.0));
    return bayer[x][y]; 
}

// ============================================================
// Color Space
// ============================================================
float3 srgb_to_linear(float3 c) { return pow(max(c, 0.0), 2.2); }
float4 srgb_to_linear(float4 c) { return float4(pow(max(c.xyz, 0.0), 2.2), c.w); }
float3 linear_to_srgb(float3 c) { return pow(max(c, 0.0), 1.0 / 2.2); }
float4 linear_to_srgb(float4 c) { return float4(pow(max(c.xyz, 0.0), 1.0 / 2.2), c.w); }

// ============================================================
// Tonemapping
// ============================================================
float3 subtle_tonemap(float3 c)
{
	// Very light filmic shaping to recover midtones without crushing art style.
	float3 t = (c * (1.0 + c / 1.8)) / (1.0 + c);
	return lerp(c, t, 0.10);
}

float3 aces_tonemap(float3 c)
{
	// Narkowicz ACES fit.
	return saturate((c * (2.51 * c + 0.03)) / (c * (2.43 * c + 0.59) + 0.14));
}

// ============================================================
// PBR - GGX Specular BRDF
// ============================================================
// Normal Distribution Function - GGX/Trowbridge-Reitz
float D_GGX(float NdotH, float roughness)
{
	float a  = roughness * roughness;
	float a2 = a * a;
	float d  = NdotH * NdotH * (a2 - 1.0) + 1.0;
	return a2 / max(3.14159265 * d * d, 1e-7);
}

// Geometry term - Smith GGX with Schlick-GGX approximation
float G_Smith(float NdotV, float NdotL, float roughness)
{
	// Use Disney remapping: k = (roughness+1)^2/8 for direct lighting
	float r = roughness + 1.0;
	float k = (r * r) / 8.0;
	float gv = NdotV / max(NdotV * (1.0 - k) + k, 1e-7);
	float gl = NdotL / max(NdotL * (1.0 - k) + k, 1e-7);
	return gv * gl;
}

// Fresnel - Schlick approximation
float3 F_Schlick(float cosTheta, float3 F0)
{
	return F0 + (1.0 - F0) * pow(1.0 - saturate(cosTheta), 5.0);
}

// ============================================================
// IBL Environment BRDF approximation (Lazarov / Karis)
// Replaces a split-sum LUT lookup with an analytic fit.
// https://www.unrealengine.com/en-US/blog/physically-based-shading-on-mobile
// ============================================================
float2 EnvBRDFApprox(float roughness, float NdotV)
{
	const float4 c0 = float4(-1.0, -0.0275, -0.572,  0.022);
	const float4 c1 = float4( 1.0,  0.0425,  1.040, -0.040);
	float4 r = roughness * c0 + c1;
	float a004 = min(r.x * r.x, exp2(-9.28 * NdotV)) * r.x + r.y;
	return float2(-1.04, 1.04) * a004 + r.zw;
}

// ============================================================
// Noise / Emissive animation helpers
// ============================================================
float hash12(float2 p)
{
	return frac(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

float smooth_rand_1d(float x, float seed)
{
	float i = floor(x);
	float f = frac(x);
	f = f * f * (3.0 - 2.0 * f);
	return lerp(hash12(float2(i, seed)), hash12(float2(i + 1.0, seed)), f);
}

float emissive_anim_factor(
	float2 uv, float t, float mask,
	float emissiveAnimStrength, float emissiveAnimScale,
	float seed)
{
	t += seed * 64.0;
	float strength = saturate(emissiveAnimStrength) * saturate(mask);
	float scale = max(emissiveAnimScale, 0.1);
	float2 gridUv = uv * scale * 2.2;
	float2 cell = floor(gridUv);
	float2 local = frac(gridUv) - 0.5;
	float cellSeed  = hash12(cell + float2(19.1, 73.7));
	float cellPhase = hash12(cell + float2(11.7,  5.3)) * 6.2831853;
	float cellSpeed = lerp(0.30, 1.35, hash12(cell + float2(37.2, 29.8)));
	float slowPulse = 0.5 + 0.5 * sin(t * cellSpeed + cellPhase);
	float drift   = smooth_rand_1d(t * (0.24 + cellSpeed * 0.18) + cellPhase, 91.0  + cellSeed * 211.0);
	float flicker = smooth_rand_1d(t * (0.75 + cellSpeed * 0.55) + cellPhase * 1.7,  173.0 + cellSeed * 307.0);
	float cellCore = smoothstep(0.72, 0.06, length(local));
	float mod = slowPulse * 0.58 + drift * 0.27 + flicker * 0.15;
	float anim = saturate(lerp(0.42, 1.36, mod) * lerp(0.88, 1.10, cellCore));
	return lerp(1.0, anim, strength);
}

// ============================================================
// Vertex Shader
// ============================================================
void base_vertex(
	uniform float4x4 wvpMat,
	uniform float4x4 worldViewMat,

#if defined(SHADOWRECEIVER) 
	uniform float4x4 texWorldViewProj1,
#if defined(PSSM_ENABLED)
	uniform float4x4 texWorldViewProj2,
	uniform float4x4 texWorldViewProj3,
#endif
#endif

#if defined(VERTEX_LIGHTING)
	uniform float4 lightPosition[MAX_LIGHTS],
	uniform float4 lightDiffuse[MAX_LIGHTS],
#if defined(SPECULAR_ENABLED) || defined(SPECULARMAP_ENABLED)
	uniform float4 lightSpecular[MAX_LIGHTS],
	uniform float materialShininess,
#endif
#endif

	in float4 iPosition   : POSITION,
	in float2 iTexCoord   : TEXCOORD0,
	in float3 iNormal     : NORMAL,
#if !defined(VERTEX_LIGHTING) && defined(NORMALMAP_ENABLED) && defined(VERTEX_TANGENTS)
	in float3 iTangent    : TANGENT,
#endif

#if defined(SKINNED)
	in float4 iBlendIndices : BLENDINDICES,
	in float4 iBlendWeights : BLENDWEIGHT,
#endif

#if defined(VERTEX_LIGHTING)
	out float3 vLightResult   : COLOR0,
#if defined(SPECULAR_ENABLED) || defined(SPECULARMAP_ENABLED)
	out float3 vSpecularResult : COLOR1,
#endif
#endif

	out float2 vTexCoord     : TEXCOORD0,
#if !defined(VERTEX_LIGHTING)
	out float3 vViewNormal   : TEXCOORD1,
#if defined(NORMALMAP_ENABLED) && defined(VERTEX_TANGENTS)
	out float3 vViewTangent  : TEXCOORD2,
#endif
	out float3 vViewPosition : TEXCOORD3,
#endif
	out float vDepth         : TEXCOORD4,
#if defined(SHADOWRECEIVER) 
	out float4 vLightSpacePos1 : TEXCOORD5,
#if defined(PSSM_ENABLED)
	out float4 vLightSpacePos2 : TEXCOORD6,
	out float4 vLightSpacePos3 : TEXCOORD7,
#endif
#endif
	out float  vObjectSeed   : TEXCOORD8,
	out float4 oPosition : POSITION
)
{
#if defined(SKINNED)
	float3x4 blendMatrix = 
		iBlendWeights.x * worldMatrix3x4Array[(int)(iBlendIndices.x + 0.5)] +
		iBlendWeights.y * worldMatrix3x4Array[(int)(iBlendIndices.y + 0.5)] +
		iBlendWeights.z * worldMatrix3x4Array[(int)(iBlendIndices.z + 0.5)] +
		iBlendWeights.w * worldMatrix3x4Array[(int)(iBlendIndices.w + 0.5)];

	float4 blendPos  = float4(mul(blendMatrix, float4(iPosition.xyz, 1.0)).xyz, 1.0);
	float3 blendNorm = mul((float3x3)blendMatrix, iNormal).xyz;
#if !defined(VERTEX_LIGHTING) && defined(NORMALMAP_ENABLED) && defined(VERTEX_TANGENTS)
	float3 blendTang = mul((float3x3)blendMatrix, iTangent).xyz;
#endif
	oPosition = mul(wvpMat, blendPos);
#else
	float4 blendPos  = iPosition;
	float3 blendNorm = iNormal;
#if !defined(VERTEX_LIGHTING) && defined(NORMALMAP_ENABLED) && defined(VERTEX_TANGENTS)
	float3 blendTang = iTangent;
#endif
	oPosition = mul(wvpMat, blendPos);
#endif

	vTexCoord = iTexCoord;

#if defined(VERTEX_LIGHTING)
	float3 vViewPosition, vViewNormal;
#endif
	vViewPosition = mul(worldViewMat, float4(blendPos.xyz, 1.0)).xyz;
	vViewNormal   = mul(worldViewMat, float4(blendNorm.xyz, 0.0)).xyz;
#if !defined(VERTEX_LIGHTING) && defined(NORMALMAP_ENABLED) && defined(VERTEX_TANGENTS)
	vViewTangent  = mul(worldViewMat, float4(blendTang.xyz, 0.0)).xyz;
#endif

	vDepth = oPosition.z;
	vObjectSeed = 0.0; // frac(dot(worldViewMat[3].xyz, float3(12.9898, 78.233, 45.164))); // Stabilize seed to prevent jitter

#if defined(SHADOWRECEIVER) 
	vLightSpacePos1 = mul(texWorldViewProj1, blendPos);
#if defined(PSSM_ENABLED)
	vLightSpacePos2 = mul(texWorldViewProj2, blendPos);
	vLightSpacePos3 = mul(texWorldViewProj3, blendPos);
#endif
#endif

#if defined(VERTEX_LIGHTING)
	// Vertex lighting: Lambertian diffuse only (GGX is too expensive per-vertex)
	// Linearize light color for correct gamma-space addition
	float3 pixelToLight = normalize(lightPosition[0].xyz - (vViewPosition * lightPosition[0].w));
	float NdotL = max(dot(normalize(vViewNormal), pixelToLight), 0.0);
	vLightResult = srgb_to_linear(lightDiffuse[0].xyz) * NdotL;

#if defined(SPECULAR_ENABLED) || defined(SPECULARMAP_ENABLED)
	// Blinn-Phong fallback for vertex specular (GGX not practical per-vertex in SM3)
	float3 viewDir = normalize(-vViewPosition);
	float3 halfVec = normalize(pixelToLight + viewDir);
	float specPower = max(materialShininess, 1.0);
	float specContrib = NdotL * pow(saturate(dot(normalize(vViewNormal), halfVec)), specPower);
	vSpecularResult = srgb_to_linear(lightSpecular[0].xyz) * specContrib;
#endif
#endif
}

// ============================================================
// Fragment (Pixel) Shader
// ============================================================
void base_fragment(
	uniform sampler2D diffuseMap  : register(s0),
#if defined(NORMALMAP_ENABLED) 
	uniform sampler2D normalMap   : register(s1),
#endif
#if defined(SPECULARMAP_ENABLED)
	uniform sampler2D specularMap : register(s2),
#endif
#if defined(EMISSIVEMAP_ENABLED)
	uniform sampler2D emissiveMap : register(s3),
#endif
	uniform sampler2D glossMap    : register(s4),
	uniform sampler2D metallicMap : register(s5),
	uniform sampler2D detailMap   : register(s6),
	uniform sampler2D detailNormalMap : register(s11),
#if !defined(SM3_LEAN_MODE)
	uniform samplerCUBE envSpecCubeMap : register(s10),
#endif

	uniform float  baseTime,
	uniform float  emissiveAnimStrength,
	uniform float  emissiveAnimSpeed,
	uniform float  emissiveAnimScale,

#if defined(SHADOWRECEIVER) 
	uniform sampler2D shadowMap1  : register(s7),
#if defined(PSSM_ENABLED)
	uniform sampler2D shadowMap2  : register(s8),
	uniform sampler2D shadowMap3  : register(s9),
#endif
	uniform float4 invShadowMapSize1,
#if defined(PSSM_ENABLED)
	uniform float4 invShadowMapSize2,
	uniform float4 invShadowMapSize3,
	uniform float4 pssmSplitPoints,
#endif
#endif

	uniform float4 sceneAmbient,

#if !defined(VERTEX_LIGHTING)
	uniform float  materialShininess,
	uniform float4 lightDiffuse[MAX_LIGHTS],
	uniform float4 lightPosition[MAX_LIGHTS],
	uniform float4 lightSpecular[MAX_LIGHTS],
	uniform float4 lightAttenuation[MAX_LIGHTS],
	uniform float4 spotLightParams[MAX_LIGHTS],
	uniform float4 lightDirection[MAX_LIGHTS],
	uniform float  lightCount,
#endif

	uniform float4 fogColour,
	uniform float4 fogParams,
	uniform float  transparency,
	uniform float  glossStrength,
	uniform float  glossBias,
	uniform float  metallicStrength,
	uniform float  metallicBias,
	uniform float  objectSpecPower,
	uniform float  objectAmbientStrength,
	uniform float  objectIBLDiffuseStrength,
	uniform float  objectIBLSpecStrength,
	uniform float  objectNormalStrength,
	uniform float  objectDiffuseBoost,
	uniform float  objectDiffuseDetailStrength,
	uniform float  objectAOFallbackStrength,
	uniform float  specAAStrength,
	uniform float  wrapDiffuse,
	uniform float  rimStrength,
	uniform float  rimPower,
#if !defined(SM3_LEAN_MODE)
	uniform float  useAcesTonemap,
	uniform float  clearcoatStrength,
	uniform float  clearcoatSmoothness,
	uniform float  wetStrength,
	uniform float  envSpecCubeStrength,
#endif
	uniform float4x4 viewMat,       // World->View (for hemisphere up direction)

#if defined(VERTEX_LIGHTING)
	in float3 vLightResult    : COLOR0,
#if defined(SPECULAR_ENABLED) || defined(SPECULARMAP_ENABLED)
	in float3 vSpecularResult : COLOR1,
#endif
#endif
	in float2 vTexCoord       : TEXCOORD0,
#if !defined(VERTEX_LIGHTING)
	in float3 vViewNormal     : TEXCOORD1,
#if defined(NORMALMAP_ENABLED) && defined(VERTEX_TANGENTS)
	in float3 vViewTangent    : TEXCOORD2,
#endif
	in float3 vViewPosition   : TEXCOORD3,
#endif
	in float  vDepth          : TEXCOORD4,
#if defined(SHADOWRECEIVER) 
	in float4 vLightSpacePos1 : TEXCOORD5,
#if defined(PSSM_ENABLED)
	in float4 vLightSpacePos2 : TEXCOORD6,
	in float4 vLightSpacePos3 : TEXCOORD7,
#endif
#endif
	in float  vObjectSeed      : TEXCOORD8,

	out float4 oColor : COLOR
#if defined(LOGDEPTH_ENABLE)	
	, out float oDepth : DEPTH
#endif
)
{
#if defined(SM3_LEAN_MODE)
	const float useAcesTonemapValue = 0.0;
	const float clearcoatStrengthValue = 0.0;
	const float clearcoatSmoothnessValue = 0.75;
	const float wetStrengthValue = 0.0;
	const float envSpecCubeStrengthValue = 0.0;
#else
	float useAcesTonemapValue = useAcesTonemap;
	float clearcoatStrengthValue = clearcoatStrength;
	float clearcoatSmoothnessValue = clearcoatSmoothness;
	float wetStrengthValue = wetStrength;
	float envSpecCubeStrengthValue = envSpecCubeStrength;
#endif

	// --------------------------------------------------------
	// Shader constants
	// --------------------------------------------------------
	const float PI               = 3.14159265;
	const float kNormalStrength  = 3.6;
	const float kDiffuseBoost    = 1.60;  // Boosted for vibrancy (sync with SM4)
	const float kDarkLift        = 0.03;  // Sync with SM4
	const float kAOStrength      = 0.25;
	const float kAOPower         = 1.35;
	const float kIBLDiffuseStr   = 0.24;
	const float kIBLSpecStr      = 0.55;
	const float kExposure        = 1.30;  // Boosted for "pop"
	const float kToneStrength    = 0.40;
	const float kRoughnessBias   = 0.03;
	const float kMetalnessBias   = -0.01;
	const float kMinRoughness    = 0.04;  // Clamp to avoid division-by-zero in GGX

	// --------------------------------------------------------
	// Shadow
	// --------------------------------------------------------
#if defined(SHADOWRECEIVER)
	float shadow;
#if defined(PSSM_ENABLED)
	if (vDepth <= pssmSplitPoints.y)
	{
#endif
		shadow = PCF_Filter(shadowMap1, vLightSpacePos1, invShadowMapSize1.xy, vDepth);
#if defined(PSSM_ENABLED)
	}
	else if (vDepth <= pssmSplitPoints.z)
		shadow = PCF_Filter(shadowMap2, vLightSpacePos2, invShadowMapSize2.xy, vDepth);
	else
		shadow = PCF_Filter(shadowMap3, vLightSpacePos3, invShadowMapSize3.xy, vDepth);
#endif
	shadow = shadow * 0.76 + 0.24;
#endif

	// --------------------------------------------------------
	// Textures - convert sRGB to linear before any math
	// --------------------------------------------------------
	float4 diffuseTex = srgb_to_linear(tex2D(diffuseMap, vTexCoord));
	float  diffuseLuma = dot(diffuseTex.xyz, float3(0.299, 0.587, 0.114));

	// Detail map (high-frequency surface variation)
	float2 detailUV  = vTexCoord * 32.0;
	float3 detailTex = tex2D(detailMap, detailUV).xyz;
	float3 detailSigned = (detailTex - 0.5) * 2.0;
	float3 detailMod = max(float3(0.35, 0.35, 0.35), 1.0 + detailSigned * (max(objectDiffuseDetailStrength, 0.0) * 0.65));

	// Apply dark-lift then detail
	float3 liftedDiffuse = diffuseTex.xyz + (1.0 - diffuseTex.xyz) * (kDarkLift * (1.0 - diffuseLuma));
	float3 diffuseAlbedo = liftedDiffuse * detailMod * (kDiffuseBoost * objectDiffuseBoost);
	diffuseAlbedo = max(diffuseAlbedo, 0.0);

	// Gloss/roughness (linear-space map, no sRGB conversion needed)
	float glossTex    = tex2D(glossMap, vTexCoord).x;
	float metallicTex = tex2D(metallicMap, vTexCoord).x;

	// Derive gloss from spec map as fallback when no explicit gloss map
	float specLuma = 0.0;
#if defined(SPECULARMAP_ENABLED)
	float3 specularTex = srgb_to_linear(tex2D(specularMap, vTexCoord).xyz);
	specLuma = dot(specularTex, float3(0.299, 0.587, 0.114));
#else
	float3 specularTex = float3(1.0, 1.0, 1.0);
#endif

	float derivedGloss    = saturate(specLuma * 0.40 + 0.08);
	float derivedMetallic = saturate((specLuma - 0.62) * 1.15 - diffuseLuma * 0.08);
	float glossMapPresence    = saturate(glossTex * 4.0);
	float metallicMapPresence = saturate(metallicTex * 4.0);
	float glossBase    = lerp(derivedGloss * 0.70, glossTex, glossMapPresence);
	float metallicBase = lerp(derivedMetallic * 0.45, metallicTex, metallicMapPresence);

	float gloss    = saturate(glossBase * glossStrength + glossBias - kRoughnessBias);
	float metallic = saturate(metallicBase * metallicStrength + metallicBias + kMetalnessBias);

	// Perceptual roughness -> linear roughness squared (gives better midrange response)
	float coatMask = saturate(clearcoatStrengthValue) * saturate((glossMapPresence * (1.0 - metallic)) + (1.0 - glossMapPresence) * saturate(specLuma * 0.35));
	float wetMask  = saturate(wetStrengthValue) * saturate(glossBase * (1.0 - metallic));
	float roughnessLinear = saturate(1.0 - gloss);
	roughnessLinear = lerp(roughnessLinear, roughnessLinear * 0.58, wetMask);
	float roughness = max(roughnessLinear * roughnessLinear, kMinRoughness);

	// Ambient Occlusion from diffuse alpha channel
	float aoAlpha = lerp(1.0, pow(saturate(diffuseTex.a), kAOPower), kAOStrength);
	float alphaFlatMask = smoothstep(0.92, 0.999, diffuseTex.a);
	float aoFallback = saturate(1.0 - specLuma * 0.35 - gloss * 0.20);
	float ao = lerp(aoAlpha, aoFallback, saturate(objectAOFallbackStrength) * alphaFlatMask);

	// Emissive
#if defined(EMISSIVEMAP_ENABLED)
	float3 emissiveTex   = srgb_to_linear(tex2D(emissiveMap, vTexCoord).xyz);
	float  emissiveMask  = saturate(dot(emissiveTex, float3(0.299, 0.587, 0.114)) * 3.2);
	float  emissiveAnim  = emissive_anim_factor(vTexCoord, baseTime * 6.2831853 * emissiveAnimSpeed, emissiveMask, emissiveAnimStrength, max(emissiveAnimScale, 0.1), vObjectSeed);
	emissiveTex *= emissiveAnim;
#else
	float3 emissiveTex = float3(0.0, 0.0, 0.0);
#endif

	// --------------------------------------------------------
	// PBR Material Parameters
	// F0: dielectric = 0.04, metal = albedo tint blended with spec map tint
	// --------------------------------------------------------
	float3 dielectricF0 = float3(0.035, 0.035, 0.035);
	float3 metalTint    = saturate(lerp(diffuseTex.xyz, specularTex, 0.78));
	float3 F0           = lerp(dielectricF0, metalTint, metallic);
	F0 = saturate(min(F0, 0.92));

	// --------------------------------------------------------
	// View-space vectors
	// --------------------------------------------------------
#if !defined(VERTEX_LIGHTING)
	float3 viewPos = vViewPosition;
	float3 geometricNormal = normalize(vViewNormal);
	float3 viewNormal;

#if defined(NORMALMAP_ENABLED)
#if defined(VERTEX_TANGENTS)
	float3 binormal = cross(vViewTangent, vViewNormal);
	float3x3 tbn = float3x3(vViewTangent, binormal, vViewNormal);
#else
	float3x3 tbn = cotangent_frame(vViewNormal, vViewPosition.xyz, vTexCoord);
#endif
	float3 normalTex = tex2D(normalMap, vTexCoord).xyz * 2.0 - 1.0;
	float2 detailNormalUV = frac(vTexCoord * 32.0);
	float2 detailNormalXY = tex2D(detailNormalMap, detailNormalUV).xy * 2.0 - 1.0;
	normalTex.xy += detailNormalXY * min(max(objectDiffuseDetailStrength, 0.0), 2.0) * 0.35;
	normalTex.xy *= (kNormalStrength * objectNormalStrength);
	normalTex.z   = sqrt(saturate(1.0 - dot(normalTex.xy, normalTex.xy)));
	viewNormal    = normalize(mul(normalTex.xyz, tbn));
#else
	viewNormal = geometricNormal;
#endif

	float3 viewDir   = normalize(-viewPos);
	float  NdotV     = saturate(dot(viewNormal, viewDir));

	// Horizon attenuation: suppress light near silhouette to reduce artifacting
	float horizonBias = 0.05;
	float horizonOcc  = pow(saturate(dot(geometricNormal, viewDir) + horizonBias), 0.5);

	// Specular AA: reduce gloss in high-frequency normal regions
	float normalVariance = 0.0;
#if defined(SPECULAR_ENABLED) || defined(SPECULARMAP_ENABLED)
	float3 dndx = ddx(viewNormal);
	float3 dndy = ddy(viewNormal);
	normalVariance = saturate((dot(dndx, dndx) + dot(dndy, dndy)) * 0.5);
#endif
	float specAAFactor = rcp(1.0 + normalVariance * specAAStrength * 8.0);

	// Micro-occlusion: darkens crevices in high-frequency normal regions
	float microOcclusion = saturate(1.0 - normalVariance * 4.0);

	// Rim lighting (simple edge highlight, viewspace)
	float rimTerm = pow(1.0 - NdotV, max(rimPower, 0.01)) * rimStrength;

	// Fresnel at view angle for IBL/energy conservation
	float3 F_view = F_Schlick(NdotV, F0);
	float coatRoughness = lerp(0.14, 0.025, saturate(clearcoatSmoothnessValue));

	// Specular occlusion: metals lose more spec in occluded areas
	float specOcc = saturate(pow(ao, 1.0 + metallic * 2.0));

	// --------------------------------------------------------
	// Hemisphere ambient (sky/ground gradient from scene ambient)
	// --------------------------------------------------------
	float3 viewSpaceUp = mul(viewMat, float4(0, 1, 0, 0)).xyz;
	float  hemiMix     = dot(viewNormal, normalize(viewSpaceUp)) * 0.5 + 0.5;
	float3 linearAmbient = srgb_to_linear(sceneAmbient.xyz);
	float3 groundAmbient = linearAmbient * 0.28; // Deepened from 0.4 for better contrast
	float3 skyAmbient    = linearAmbient;
	float3 hemiAmbient   = lerp(groundAmbient, skyAmbient, hemiMix);

	// Start accumulating light
	float3 ambientFloor   = float3(0.005, 0.005, 0.005) * objectAmbientStrength;
	float3 lightResult    = max(hemiAmbient * objectAmbientStrength * microOcclusion, ambientFloor);
	float3 specularResult = float3(0.0, 0.0, 0.0);

	// --------------------------------------------------------
	// Direct Lights - GGX BRDF
	// --------------------------------------------------------
#if MAX_LIGHTS > 1
	[unroll] for (int i = 0; i < MAX_LIGHTS; ++i)
	{
		if (i >= int(lightCount)) break;
#else
	{
		const int i = 0;
#endif
		float3 pixelToLight = lightPosition[i].xyz - (viewPos * lightPosition[i].w);
		float  d = length(pixelToLight);
		pixelToLight /= d;

		// Distance attenuation
		float attenuation = saturate(1.0 / 
			(lightAttenuation[i].y + d * (lightAttenuation[i].z + d * lightAttenuation[i].w)));

		// Spotlight cone attenuation (transparent for directional lights via power=0)
		float spotLinear  = saturate((dot(pixelToLight, -lightDirection[i].xyz) - spotLightParams[i].y) / 
		                             max(spotLightParams[i].x - spotLightParams[i].y, 1e-5));
		float spotCone    = pow(smoothstep(0.0, 1.0, spotLinear), spotLightParams[i].z);
		attenuation *= spotCone;

#if defined(SHADOWRECEIVER)
		attenuation *= shadow;
#endif
		attenuation *= horizonOcc;

		float NdotL = saturate(dot(viewNormal, pixelToLight));

		// Wrapped diffuse (softer terminator)
		float wrappedNdotL = saturate((NdotL + wrapDiffuse) / max(1.0 + wrapDiffuse, 1e-3));
		float3 lightLin    = srgb_to_linear(lightDiffuse[i].xyz);
		lightResult += lightLin * attenuation * wrappedNdotL;

#if defined(SPECULAR_ENABLED) || defined(SPECULARMAP_ENABLED)
		// GGX Cook-Torrance specular
		float3 halfVec = normalize(pixelToLight + viewDir);
		float  NdotH   = saturate(dot(viewNormal, halfVec));
		float  HdotV   = saturate(dot(halfVec, viewDir));

		float  D = D_GGX(NdotH, roughness);
		float  G = G_Smith(NdotV, NdotL, roughness);
		float3 F = F_Schlick(HdotV, F0);

		// Full Cook-Torrance denominator; NdotL pulled out to cancel with rendering equation
		float3 specTerm = (D * G * F) / max(4.0 * NdotV * NdotL, 1e-4);
		float3 specLightLin = srgb_to_linear(lightSpecular[i].xyz);
		specularResult += specLightLin * attenuation * specTerm * NdotL * specAAFactor;
#endif
	}

	// --------------------------------------------------------
	// IBL - Image-Based Lighting approximation
	// --------------------------------------------------------
	// Diffuse IBL: hemisphere-filtered ambient, attenuated by (1-F) * (1-metallic)
	float3 diffuseEnergy = (1.0 - F_view) * (1.0 - metallic);
	float3 iblDiffuse = hemiAmbient * diffuseAlbedo * diffuseEnergy * 
	                    (kIBLDiffuseStr * objectIBLDiffuseStrength * ao);

	// Specular IBL: use Lazarov/Karis split-sum approximation
	float2 envBRDF = EnvBRDFApprox(roughness, NdotV);
	float3 envSpec = F0 * envBRDF.x + envBRDF.y;
	float  iblGloss = lerp(0.08, 1.0, saturate(1.0 - roughness * roughness));
	float  iblMetalBoost = lerp(1.0, 2.25, metallic); // Increased metal boost for "pop"
	float nonMetalSpecDampen = lerp(0.70, 1.0, metallic);
	float3 iblSpec = skyAmbient * envSpec * iblGloss * 
	                 (kIBLSpecStr * objectIBLSpecStrength * ao * iblMetalBoost) * specOcc * nonMetalSpecDampen;
	float3 reflDir = reflect(-viewDir, viewNormal);
	float envCubeStrength = saturate(envSpecCubeStrengthValue);
	float3 envCubeSpec = float3(0.0, 0.0, 0.0);
	float3 coatEnvCube = float3(0.0, 0.0, 0.0);
#if !defined(SM3_LEAN_MODE)
	if (envCubeStrength > 1e-4)
	{
		envCubeSpec = srgb_to_linear(texCUBE(envSpecCubeMap, reflDir).xyz);
		coatEnvCube = envCubeSpec;
	}
#endif
	iblSpec += envCubeSpec * envSpec * envCubeStrength * ao * nonMetalSpecDampen;

	float3 coatF0 = float3(0.04, 0.04, 0.04);
	float2 coatEnvBRDF = EnvBRDFApprox(coatRoughness, NdotV);
	float3 coatEnvSpec = coatF0 * coatEnvBRDF.x + coatEnvBRDF.y;
	float3 clearcoatIBL = coatEnvCube * coatEnvSpec * coatMask * envCubeStrength * ao;

	// --------------------------------------------------------
	// Combine: diffuse contribution
	// --------------------------------------------------------
	oColor.xyz  = lightResult * diffuseAlbedo * diffuseEnergy * ao;
	oColor.xyz += diffuseAlbedo * rimTerm * 0.18;
	oColor.xyz += iblDiffuse + iblSpec * saturate(specularTex + metalTint * metallic);
	oColor.xyz += clearcoatIBL;

#if defined(SPECULAR_ENABLED) || defined(SPECULARMAP_ENABLED)
	// Direct specular, tinted by F (Fresnel) and spec map
	oColor.xyz += specularResult * saturate(specularTex + metalTint * metallic * 0.5) * specOcc * nonMetalSpecDampen;
	float3 coatF = F_Schlick(NdotV, coatF0);
	oColor.xyz += specularResult * coatF * (coatMask * 0.22 + wetMask * 0.28) * specOcc;
#endif

	// Keep uniforms alive in low-feature permutations (avoids optimizer stripping uniforms 
	// that BZ98R may still try to bind, which would cause DX9 parameter errors)
	oColor.xyz *= (1.0 + (gloss + metallic + materialShininess + objectSpecPower + 
	    objectAmbientStrength + objectIBLDiffuseStrength + objectIBLSpecStrength + 
	    objectNormalStrength + objectDiffuseBoost + objectDiffuseDetailStrength + objectAOFallbackStrength +
	    useAcesTonemapValue + clearcoatStrengthValue + clearcoatSmoothnessValue + wetStrengthValue + envSpecCubeStrengthValue +
	    specAAStrength + wrapDiffuse + rimStrength + rimPower + 
	    emissiveAnimStrength + emissiveAnimSpeed + emissiveAnimScale) * 1e-6);

#else
	// --------------------------------------------------------
	// Vertex Lighting path (simplified)
	// --------------------------------------------------------
	float3 lightResult = vLightResult;
#if defined(SHADOWRECEIVER)
	lightResult *= shadow;
#endif
	// Ambient - linearize here
	float3 linearAmbient2 = srgb_to_linear(sceneAmbient.xyz);
	lightResult += max(linearAmbient2 * objectAmbientStrength, float3(0.005, 0.005, 0.005) * objectAmbientStrength);

	float3 diffuseEnergy = float3(1.0, 1.0, 1.0);
	oColor.xyz = lightResult * diffuseAlbedo * diffuseEnergy;

#if defined(SPECULAR_ENABLED) || defined(SPECULARMAP_ENABLED)
	float3 specularResult = vSpecularResult;
	oColor.xyz += specularResult * specularTex;
#endif

	oColor.xyz *= (1.0 + (gloss + metallic + objectSpecPower + objectAmbientStrength + 
	    objectIBLDiffuseStrength + objectIBLSpecStrength + objectNormalStrength + 
	    objectDiffuseBoost + objectDiffuseDetailStrength + objectAOFallbackStrength +
	    useAcesTonemapValue + clearcoatStrengthValue + clearcoatSmoothnessValue + wetStrengthValue + envSpecCubeStrengthValue +
	    specAAStrength + wrapDiffuse + 
	    rimStrength + rimPower + emissiveAnimStrength + emissiveAnimSpeed + emissiveAnimScale) * 1e-6);
#endif

	// --------------------------------------------------------
	// Clamp, Exposure, Tonemapping
	// --------------------------------------------------------
	oColor.xyz = min(oColor.xyz, 3.0);
	float3 exposedColor = oColor.xyz * kExposure;
	float3 subtleMapped = lerp(exposedColor, subtle_tonemap(exposedColor), kToneStrength);
	float3 acesMapped = aces_tonemap(exposedColor);
	oColor.xyz = lerp(subtleMapped, acesMapped, step(0.5, useAcesTonemapValue));

	// Emissive added AFTER tonemapping to preserve full bloom energy
#if defined(EMISSIVEMAP_ENABLED)
	oColor.xyz += emissiveTex * 1.5;
#endif

	// --------------------------------------------------------
	// Fog (in linear space, then convert together)
	// --------------------------------------------------------
	float fogValue = saturate((vDepth - fogParams.y) * fogParams.w);
	oColor.xyz = lerp(oColor.xyz, srgb_to_linear(fogColour.xyz), fogValue);

	// --------------------------------------------------------
	// Convert linear -> sRGB for display output
	// --------------------------------------------------------
	oColor.xyz = linear_to_srgb(oColor.xyz);

	// --------------------------------------------------------
	// Alpha / Transparency dithering
	// --------------------------------------------------------
	float alpha = saturate(transparency);
	if (alpha < 0.99)
	{
		float dither = GetDither(vTexCoord * 1024.0);
		clip(alpha - dither);
	}
	oColor.a = 1.0;

#if defined(LOGDEPTH_ENABLE)
	const float C = 0.1;
	const float offset = 1.0;
	const float kInvLogDepthDenom = 0.054286812;
	oDepth = log(C * vDepth + offset) * kInvLogDepthDenom;
#endif
}


