// CR_base-sm4.hlsl - DX11 (SM4/SM5) PBR shader for BZ98R
// Physically-based: GGX Cook-Torrance specular, linear-space lighting,
// energy-conserving diffuse, Fresnel metal/dielectric split,
// hemisphere ambient, IBL split-sum approximation, AO, specular occlusion.

// ============================================================
// Shadow Filtering
// ============================================================
#if defined(SHADOWRECEIVER) 
float PCF_Filter(in Texture2D map, in SamplerState sam, in float4 uv, in float2 invMapSize)
{
	uv /= uv.w;
	uv.z = min(uv.z, 1.0);
#if PCF_SIZE > 1
	float2 pixel = uv.xy / invMapSize - float2(float(PCF_SIZE-1)*0.5, float(PCF_SIZE-1)*0.5);
	float2 c = floor(pixel);
	float2 f = frac(pixel);

	float kernel[PCF_SIZE*PCF_SIZE];
	{
		[unroll] for (int y = 0; y < PCF_SIZE; ++y)
			[unroll] for (int x = 0; x < PCF_SIZE; ++x)
			{
				int i = y * PCF_SIZE + x;
				kernel[i] = step(uv.z, map.Sample(sam, (c + float2(x, y)) * invMapSize).x);
			}
	}

	float4 sum = float4(0, 0, 0, 0);
	{
		[unroll] for (int y = 0; y < PCF_SIZE - 1; ++y)
			[unroll] for (int x = 0; x < PCF_SIZE - 1; ++x)
			{
				int i = y * PCF_SIZE + x;
				sum += float4(kernel[i], kernel[i+1], kernel[i+PCF_SIZE], kernel[i+PCF_SIZE+1]);
			}
	}
	return lerp(lerp(sum.x, sum.y, f.x), lerp(sum.z, sum.w, f.x), f.y) / float((PCF_SIZE-1)*(PCF_SIZE-1));
#else
	return step(uv.z, map.Sample(sam, uv.xy).x);
#endif
}
#endif

// ============================================================
// Normal Map Helpers
// ============================================================
#if defined(NORMALMAP_ENABLED) && !defined(VERTEX_TANGENTS)
// Cotangent frame from geometry (no vertex tangents needed)
// http://www.thetenthplanet.de/archives/1180
float3x3 cotangent_frame(float3 N, float3 p, float2 uv)
{
	float3 dp1  = ddx(p); float3 dp2  = ddy(p);
	float2 duv1 = ddx(uv); float2 duv2 = ddy(uv);
	float3 dp2perp = cross(N, dp2);
	float3 dp1perp = cross(dp1, N);
	float3 T = dp2perp * duv1.x + dp1perp * duv2.x;
	float3 B = dp2perp * duv1.y + dp1perp * duv2.y;
	float invmax = rsqrt(max(dot(T,T), dot(B,B)) + 1e-30);
	return float3x3(T * invmax, B * invmax, N);
}
#endif

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
	float3 t = (c * (1.0 + c / 1.8)) / (1.0 + c);
	return lerp(c, t, 0.10);
}

// ============================================================
// PBR - GGX Specular BRDF
// ============================================================
float D_GGX(float NdotH, float roughness)
{
	float a  = roughness * roughness;
	float a2 = a * a;
	float d  = NdotH * NdotH * (a2 - 1.0) + 1.0;
	return a2 / max(3.14159265 * d * d, 1e-7);
}

float G_Smith(float NdotV, float NdotL, float roughness)
{
	float r = roughness + 1.0;
	float k = (r * r) / 8.0;
	float gv = NdotV / max(NdotV * (1.0 - k) + k, 1e-7);
	float gl = NdotL / max(NdotL * (1.0 - k) + k, 1e-7);
	return gv * gl;
}

float3 F_Schlick(float cosTheta, float3 F0)
{
	return F0 + (1.0 - F0) * pow(1.0 - saturate(cosTheta), 5.0);
}

// ============================================================
// IBL Environment BRDF approximation (Lazarov/Karis)
// Analytic fit to split-sum environment BRDF LUT lookup.
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
	float2 gridUv  = uv * scale * 2.2;
	float2 cell    = floor(gridUv);
	float2 local   = frac(gridUv) - 0.5;
	float cellSeed  = hash12(cell + float2(19.1, 73.7));
	float cellPhase = hash12(cell + float2(11.7,  5.3)) * 6.2831853;
	float cellSpeed = lerp(0.30, 1.35, hash12(cell + float2(37.2, 29.8)));
	float slowPulse = 0.5 + 0.5 * sin(t * cellSpeed + cellPhase);
	float drift   = smooth_rand_1d(t * (0.24 + cellSpeed * 0.18) + cellPhase, 91.0  + cellSeed * 211.0);
	float flicker = smooth_rand_1d(t * (0.75 + cellSpeed * 0.55) + cellPhase * 1.7, 173.0 + cellSeed * 307.0);
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
	uniform float  materialShininess,
#endif
#endif

	in float4 iPosition   : POSITION,
	in float2 iTexCoord   : TEXCOORD0,
	in float3 iNormal     : NORMAL,
#if defined(NORMALMAP_ENABLED) && defined(VERTEX_TANGENTS)
	in float3 iTangent    : TANGENT,
#endif

#if defined(SKINNED)
	in float4 iBlendIndices : BLENDINDICES,
	in float4 iBlendWeights : BLENDWEIGHT,
#endif

#if defined(VERTEX_LIGHTING)
	out float3 vLightResult    : COLOR0,
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
	out float  vDepth         : TEXCOORD4,
#if defined(SHADOWRECEIVER) 
	out float4 vLightSpacePos1 : TEXCOORD5,
#if defined(PSSM_ENABLED)
	out float4 vLightSpacePos2 : TEXCOORD6,
	out float4 vLightSpacePos3 : TEXCOORD7,
#endif
#endif
	out float  vObjectSeed   : TEXCOORD8,
	out float4 oPosition : SV_POSITION
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
#if defined(NORMALMAP_ENABLED) && defined(VERTEX_TANGENTS)
	float3 blendTang = mul((float3x3)blendMatrix, iTangent).xyz;
#endif
	oPosition = mul(wvpMat, blendPos);
#else
	float4 blendPos  = iPosition;
	float3 blendNorm = iNormal;
#if defined(NORMALMAP_ENABLED) && defined(VERTEX_TANGENTS)
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
	// Vertex lighting: Lambertian diffuse (linearized)
	float3 pixelToLight = normalize(lightPosition[0].xyz - (vViewPosition * lightPosition[0].w));
	float  NdotL = max(dot(normalize(vViewNormal), pixelToLight), 0.0);
	vLightResult = srgb_to_linear(lightDiffuse[0].xyz) * NdotL;

#if defined(SPECULAR_ENABLED) || defined(SPECULARMAP_ENABLED)
	// Blinn-Phong fallback for vertex specular
	float3 viewDir = normalize(-vViewPosition);
	float3 halfVec = normalize(pixelToLight + viewDir);
	float  specContrib = NdotL * pow(saturate(dot(normalize(vViewNormal), halfVec)), max(materialShininess, 1.0));
	vSpecularResult = srgb_to_linear(lightSpecular[0].xyz) * specContrib;
#endif
#endif
}

// ============================================================
// Fragment (Pixel) Shader
// ============================================================
void base_fragment(
	uniform Texture2D  diffuseMap  : register(t0),
	uniform SamplerState diffuseSam : register(s0),
#if defined(NORMALMAP_ENABLED)
	uniform Texture2D  normalMap   : register(t1),
	uniform SamplerState normalSam : register(s1),
#endif
#if defined(SPECULARMAP_ENABLED)
	uniform Texture2D  specularMap : register(t2),
	uniform SamplerState specularSam : register(s2),
#endif
#if defined(EMISSIVEMAP_ENABLED)
	uniform Texture2D  emissiveMap : register(t3),
	uniform SamplerState emissiveSam : register(s3),
#endif
	uniform Texture2D  glossMap    : register(t4),
	uniform SamplerState glossSam  : register(s4),
	uniform Texture2D  metallicMap : register(t5),
	uniform SamplerState metallicSam : register(s5),
	uniform Texture2D  detailMap   : register(t9),
	uniform SamplerState detailSam : register(s9),

#if defined(SHADOWRECEIVER)
	uniform Texture2D  shadowMap1  : register(t6),
	uniform SamplerState shadowSam1 : register(s6),
#if defined(PSSM_ENABLED)
	uniform Texture2D  shadowMap2  : register(t7),
	uniform SamplerState shadowSam2 : register(s7),
	uniform Texture2D  shadowMap3  : register(t8),
	uniform SamplerState shadowSam3 : register(s8),
#endif
	uniform float4 invShadowMapSize1,
#if defined(PSSM_ENABLED)
	uniform float4 invShadowMapSize2,
	uniform float4 invShadowMapSize3,
	uniform float4 pssmSplitPoints,
#endif
#endif

	uniform float  baseTime,
	uniform float  emissiveAnimStrength,
	uniform float  emissiveAnimSpeed,
	uniform float  emissiveAnimScale,
	uniform float4 sceneAmbient,

#if !defined(VERTEX_LIGHTING)
#if defined(SPECULAR_ENABLED) || defined(SPECULARMAP_ENABLED)
	uniform float  materialShininess,
#endif
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
	uniform float  objectNormalStrength,
	uniform float  objectDiffuseBoost,
	uniform float  objectDiffuseDetailStrength,
	uniform float  specAAStrength,
	uniform float  wrapDiffuse,
	uniform float  rimStrength,
	uniform float  rimPower,
	uniform float  objectIBLDiffuseStrength,
	uniform float  objectIBLSpecStrength,
	uniform float  objectAmbientStrength,
	uniform float4x4 viewMat,        // For hemisphere up direction

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
	in float  vObjectSeed     : TEXCOORD8,
	out float4 oColor : SV_TARGET
#if defined(LOGDEPTH_ENABLE)
	, out float oDepth : SV_DEPTH
#endif
)
{
	// --------------------------------------------------------
	// Shader constants
	// --------------------------------------------------------
	const float PI            = 3.14159265;
	const float kNormalStr    = 2.8;
	const float kDiffuseBoost = 1.45;
	const float kDarkLift     = 0.08;
	const float kAOStrength   = 0.25;
	const float kAOPower      = 1.35;
	const float kIBLDiffStr   = 0.24;
	const float kIBLSpecStr   = 0.55;
	const float kExposure     = 1.20;
	const float kToneStrength = 0.55;
	const float kRoughnessBias= 0.02;
	const float kMetalnessBias= -0.06;
	const float kMinRoughness = 0.04;

	// --------------------------------------------------------
	// Shadow
	// --------------------------------------------------------
#if defined(SHADOWRECEIVER)
	float shadow;
#if defined(PSSM_ENABLED)
	if (vDepth <= pssmSplitPoints.y)
	{
#endif
		shadow = PCF_Filter(shadowMap1, shadowSam1, vLightSpacePos1, invShadowMapSize1.xy);
#if defined(PSSM_ENABLED)
	}
	else if (vDepth <= pssmSplitPoints.z)
		shadow = PCF_Filter(shadowMap2, shadowSam2, vLightSpacePos2, invShadowMapSize2.xy);
	else
		shadow = PCF_Filter(shadowMap3, shadowSam3, vLightSpacePos3, invShadowMapSize3.xy);
#endif
	shadow = shadow * 0.76 + 0.24;
#endif

	// --------------------------------------------------------
	// Textures - convert sRGB -> linear before any math
	// --------------------------------------------------------
	float4 diffuseTex  = srgb_to_linear(diffuseMap.Sample(diffuseSam, vTexCoord));
	float  diffuseLuma = dot(diffuseTex.xyz, float3(0.299, 0.587, 0.114));

	// Detail map
	float2 detailUV   = vTexCoord * 12.0;
	float3 detailTex  = detailMap.Sample(detailSam, detailUV).xyz;
	float3 detailBlend = lerp(float3(0.5, 0.5, 0.5), detailTex, objectDiffuseDetailStrength);
	float3 liftedDiffuse = diffuseTex.xyz + (1.0 - diffuseTex.xyz) * (kDarkLift * (1.0 - diffuseLuma));
	float3 diffuseAlbedo = max(liftedDiffuse * (detailBlend * 2.0) * (kDiffuseBoost * objectDiffuseBoost), 0.0);

	// Gloss / metallic (linear maps)
	float glossTex    = glossMap.Sample(glossSam, vTexCoord).x;
	float metallicTex = metallicMap.Sample(metallicSam, vTexCoord).x;

	// Specular / tint map
	float specLuma = 0.0;
#if defined(SPECULARMAP_ENABLED)
	float3 specularTex = srgb_to_linear(specularMap.Sample(specularSam, vTexCoord).xyz);
	specLuma = dot(specularTex, float3(0.299, 0.587, 0.114));
#else
	float3 specularTex = float3(1.0, 1.0, 1.0);
#endif

	// Derive gloss/metallic from spec map as fallback
	float derivedGloss    = saturate(specLuma * 0.55);
	float derivedMetallic = saturate(specLuma * 0.30 - diffuseLuma * 0.18 - 0.05);
	float glossMapPres    = saturate(glossTex * 4.0);
	float metalMapPres    = saturate(metallicTex * 4.0);
	float glossBase    = lerp(derivedGloss * 0.70, glossTex, glossMapPres);
	float metallicBase = lerp(derivedMetallic * 0.35, metallicTex, metalMapPres);

	float gloss    = saturate(glossBase * glossStrength + glossBias - kRoughnessBias);
	float metallic = saturate(metallicBase * metallicStrength + metallicBias + kMetalnessBias);

	// Perceptual roughness, squared for linear perceptual mapping
	float roughnessLinear = saturate(1.0 - gloss);
	float roughness = max(roughnessLinear * roughnessLinear, kMinRoughness);

	// AO from diffuse alpha
	float ao = lerp(1.0, pow(saturate(diffuseTex.a), kAOPower), kAOStrength);

	// Emissive
#if defined(EMISSIVEMAP_ENABLED)
	float3 emissiveTex   = srgb_to_linear(emissiveMap.Sample(emissiveSam, vTexCoord).xyz);
	float  emissiveMask  = saturate(dot(emissiveTex, float3(0.299, 0.587, 0.114)) * 3.2);
	float  emissiveAnim  = emissive_anim_factor(vTexCoord, baseTime * 6.2831853 * emissiveAnimSpeed, emissiveMask, emissiveAnimStrength, max(emissiveAnimScale, 0.1), vObjectSeed);
	emissiveTex = float3(1.0, 0.0, 1.0) * (0.5 + 0.5 * sin(baseTime * 5.0)); // SIMPLE PULSE TEST
#else
	float3 emissiveTex = float3(0.0, 0.0, 0.0);
#endif

	// --------------------------------------------------------
	// PBR Material
	// --------------------------------------------------------
	float3 dielectricF0 = float3(0.04, 0.04, 0.04);
	float3 metalTint    = saturate(lerp(diffuseTex.xyz, specularTex, 0.65));
	float3 F0           = saturate(min(lerp(dielectricF0, metalTint, metallic), 0.92));

	// --------------------------------------------------------
	// Per-pixel lighting path
	// --------------------------------------------------------
#if !defined(VERTEX_LIGHTING)
	float3 viewPos = vViewPosition;
	float3 geometricNormal = normalize(vViewNormal);
	float3 viewNormal;

#if defined(NORMALMAP_ENABLED)
#if defined(VERTEX_TANGENTS)
	float3 binormal  = cross(vViewTangent, vViewNormal);
	float3x3 tbn     = float3x3(vViewTangent, binormal, vViewNormal);
#else
	float3x3 tbn = cotangent_frame(vViewNormal, vViewPosition.xyz, vTexCoord);
#endif
	float3 normalTex = normalMap.Sample(normalSam, vTexCoord).xyz * 2.0 - 1.0;
	normalTex.xy    *= kNormalStr * objectNormalStrength;
	normalTex.z      = sqrt(saturate(1.0 - dot(normalTex.xy, normalTex.xy)));
	viewNormal       = normalize(mul(normalTex.xyz, tbn));
#else
	viewNormal = geometricNormal;
#endif

	float3 viewDir = normalize(-viewPos);
	float  NdotV   = saturate(dot(viewNormal, viewDir));

	// Horizon attenuation
	float horizonOcc = pow(saturate(dot(geometricNormal, viewDir) + 0.05), 0.5);

	// Specular AA
	float3 dndx = ddx(viewNormal);
	float3 dndy = ddy(viewNormal);
	float  normalVariance = saturate((dot(dndx,dndx) + dot(dndy,dndy)) * 0.5);
	float  specAAFactor   = rcp(1.0 + normalVariance * specAAStrength * 8.0);
	float  microOcclusion = saturate(1.0 - normalVariance * 4.0);

	// Rim
	float rimTerm = pow(1.0 - NdotV, max(rimPower, 0.01)) * rimStrength;

	// Fresnel at view angle
	float3 F_view = F_Schlick(NdotV, F0);

	// Specular occlusion
	float specOcc = saturate(pow(ao, 1.0 + metallic * 2.0));

	// --------------------------------------------------------
	// Hemisphere ambient
	// --------------------------------------------------------
	float3 viewSpaceUp  = mul(viewMat, float4(0, 1, 0, 0)).xyz;
	float  hemiMix      = dot(viewNormal, normalize(viewSpaceUp)) * 0.5 + 0.5;
	float3 linearAmbient= srgb_to_linear(sceneAmbient.xyz);
	float3 groundAmbient= linearAmbient * 0.4;
	float3 skyAmbient   = linearAmbient;
	float3 hemiAmbient  = lerp(groundAmbient, skyAmbient, hemiMix);

	float3 lightResult    = hemiAmbient * objectAmbientStrength * microOcclusion;
	float3 specularResult = float3(0.0, 0.0, 0.0);

	// --------------------------------------------------------
	// Direct Lights - GGX BRDF
	// --------------------------------------------------------
#if MAX_LIGHTS > 1
	for (int i = 0; i < MAX_LIGHTS; ++i)
	{
		if (i >= int(lightCount)) break;
#else
	{
		const int i = 0;
#endif
		float3 pixelToLight = lightPosition[i].xyz - (viewPos * lightPosition[i].w);
		float  d = length(pixelToLight);
		pixelToLight /= d;

		float attenuation = saturate(1.0 /
			(lightAttenuation[i].y + d * (lightAttenuation[i].z + d * lightAttenuation[i].w)));

		float spotLinear = saturate((dot(pixelToLight, -lightDirection[i].xyz) - spotLightParams[i].y) /
		                            max(spotLightParams[i].x - spotLightParams[i].y, 1e-5));
		attenuation *= pow(smoothstep(0.0, 1.0, spotLinear), spotLightParams[i].z);

#if defined(SHADOWRECEIVER)
		attenuation *= shadow;
#endif
		attenuation *= horizonOcc;

		float NdotL = saturate(dot(viewNormal, pixelToLight));

		// Wrapped diffuse
		float wrappedNdotL = saturate((NdotL + wrapDiffuse) / max(1.0 + wrapDiffuse, 1e-3));
		lightResult += srgb_to_linear(lightDiffuse[i].xyz) * attenuation * wrappedNdotL;

#if defined(SPECULAR_ENABLED) || defined(SPECULARMAP_ENABLED)
		// GGX Cook-Torrance
		float3 halfVec = normalize(pixelToLight + viewDir);
		float  NdotH   = saturate(dot(viewNormal, halfVec));
		float  HdotV   = saturate(dot(halfVec, viewDir));

		float  D = D_GGX(NdotH, roughness);
		float  G = G_Smith(NdotV, NdotL, roughness);
		float3 F = F_Schlick(HdotV, F0);

		float3 specTerm = (D * G * F) / max(4.0 * NdotV * NdotL, 1e-4);
		specularResult += srgb_to_linear(lightSpecular[i].xyz) * attenuation * specTerm * NdotL * specAAFactor;
#endif
	}

	// --------------------------------------------------------
	// IBL
	// --------------------------------------------------------
	float3 diffuseEnergy = (1.0 - F_view) * (1.0 - metallic);

	float3 iblDiffuse = hemiAmbient * diffuseAlbedo * diffuseEnergy *
	                    (kIBLDiffStr * objectIBLDiffuseStrength * ao);

	float2 envBRDF    = EnvBRDFApprox(roughness, NdotV);
	float3 envSpec    = F0 * envBRDF.x + envBRDF.y;
	float  iblGloss   = lerp(0.08, 1.0, saturate(1.0 - roughness * roughness));
	float  iblMetBoost= lerp(1.0, 1.85, metallic);
	float3 iblSpec    = skyAmbient * envSpec * iblGloss *
	                    (kIBLSpecStr * objectIBLSpecStrength * ao * iblMetBoost) * specOcc;

	// --------------------------------------------------------
	// Combine
	// --------------------------------------------------------
	oColor.xyz  = lightResult * diffuseAlbedo * diffuseEnergy * ao;
	oColor.xyz += diffuseAlbedo * rimTerm * 0.18;
	oColor.xyz += iblDiffuse + iblSpec * saturate(specularTex + metalTint * metallic);

#if defined(SPECULAR_ENABLED) || defined(SPECULARMAP_ENABLED)
	oColor.xyz += specularResult * saturate(specularTex + metalTint * metallic * 0.5) * specOcc;
#endif

	// Keep uniforms alive for permutation stability
	oColor.xyz *= (1.0 + (gloss + metallic + objectAmbientStrength +
	    objectIBLDiffuseStrength + objectIBLSpecStrength + objectNormalStrength + 
	    objectDiffuseBoost + objectDiffuseDetailStrength + specAAStrength + wrapDiffuse + 
	    rimStrength + rimPower + emissiveAnimStrength + emissiveAnimSpeed + emissiveAnimScale
#if defined(SPECULAR_ENABLED) || defined(SPECULARMAP_ENABLED)
	    + materialShininess
#endif
	    ) * 1e-6);

#else
	// --------------------------------------------------------
	// Vertex Lighting path
	// --------------------------------------------------------
	float3 lightResult = vLightResult;
#if defined(SHADOWRECEIVER)
	lightResult *= shadow;
#endif
	float3 linearAmbient2 = srgb_to_linear(sceneAmbient.xyz);
	lightResult += linearAmbient2 * objectAmbientStrength;

	float3 diffuseEnergy = float3(1.0, 1.0, 1.0);
	oColor.xyz = lightResult * diffuseAlbedo * diffuseEnergy;

#if defined(SPECULAR_ENABLED) || defined(SPECULARMAP_ENABLED)
	oColor.xyz += vSpecularResult * specularTex;
#endif

	oColor.xyz *= (1.0 + (gloss + metallic + objectAmbientStrength + 
	    objectIBLDiffuseStrength + objectIBLSpecStrength + objectNormalStrength + 
	    objectDiffuseBoost + objectDiffuseDetailStrength + specAAStrength + wrapDiffuse + 
	    rimStrength + rimPower + emissiveAnimStrength + emissiveAnimSpeed + emissiveAnimScale) * 1e-6);
#endif

	// --------------------------------------------------------
	// Clamp, Exposure, Tonemapping
	// --------------------------------------------------------
	oColor.xyz = min(oColor.xyz, 3.0);
	float3 exposed = oColor.xyz * kExposure;
	oColor.xyz = lerp(exposed, subtle_tonemap(exposed), kToneStrength);

	// Emissive after tonemapping to preserve bloom energy
#if defined(EMISSIVEMAP_ENABLED)
	oColor.xyz += emissiveTex * 1.5;
#endif

	// --------------------------------------------------------
	// Fog (linear space)
	// --------------------------------------------------------
	float fogValue = saturate((vDepth - fogParams.y) * fogParams.w);
	oColor.xyz = lerp(oColor.xyz, srgb_to_linear(fogColour.xyz), fogValue);

	// --------------------------------------------------------
	// linear -> sRGB output
	// --------------------------------------------------------
	oColor.xyz = linear_to_srgb(oColor.xyz);
	oColor.a   = saturate(transparency);

#if defined(LOGDEPTH_ENABLE)
	const float C = 0.1;
	const float far = 1e+09;
	oDepth = log(C * vDepth + 1.0) / log(C * far + 1.0);
#endif
}
