
// ----------------------------------------------------------------------------
// CR_terrain.hlsl - REBOOTED MINIMAL SHADER (GROUND ZERO)
// ----------------------------------------------------------------------------

uniform sampler2D diffuseMap : register(s0);

// Vertex to Fragment Input
struct v2f {
	float4 position : POSITION;
	float2 uv : TEXCOORD0;
	float4 color : COLOR0;
	float depth : TEXCOORD5;
};

#if defined(NORMALMAP_ENABLED) && !defined(VERTEX_TANGENTS)
// compute cotangent frame from normal, position, and texcoord
// http://www.thetenthplanet.de/archives/1180
float3x3 cotangent_frame(float3 N, float3 p, float2 uv)
{
	// get edge vectors of the pixel triangle
	float3 dp1 = ddx(p);
	float3 dp2 = ddy(p);
	float2 duv1 = ddx(uv);
	float2 duv2 = ddy(uv);

	// solve the linear system
	float3 dp2perp = cross(N, dp2);
	float3 dp1perp = cross(dp1, N);
	float3 T = dp2perp * duv1.x + dp1perp * duv2.x;
	float3 B = dp2perp * duv1.y + dp1perp * duv2.y;

	// construct a scale-invariant frame
	float invmax = rsqrt(max(dot(T, T), dot(B, B)) + 1e-30);
	T *= invmax;
	B *= invmax;
	return float3x3(T, B, N);
}
#endif

#if defined(SHADOWRECEIVER)
float PCF_Filter(sampler2D shadowMap, float4 lightSpacePos, float4 invmapSize)
{
	float2 uv = lightSpacePos.xy / lightSpacePos.w;
	float z = lightSpacePos.z / lightSpacePos.w;

	float shadow = 0.0;
	float2 offsets[4] = {
		float2(-0.5, -0.5), float2(0.5, -0.5),
		float2(-0.5,  0.5), float2(0.5,  0.5)
	};

	shadow += (tex2D(shadowMap, uv + offsets[0] * invmapSize.xy).x >= z) ? 1.0 : 0.0;
	shadow += (tex2D(shadowMap, uv + offsets[1] * invmapSize.xy).x >= z) ? 1.0 : 0.0;
	shadow += (tex2D(shadowMap, uv + offsets[2] * invmapSize.xy).x >= z) ? 1.0 : 0.0;
	shadow += (tex2D(shadowMap, uv + offsets[3] * invmapSize.xy).x >= z) ? 1.0 : 0.0;

	return shadow * 0.25;
}
#endif

float3 subtle_tonemap(float3 c)
{
	// Very light filmic shaping to recover midtones without crushing art style.
	float3 t = (c * (1.0 + c / 1.8)) / (1.0 + c);
	return lerp(c, t, 0.10);
}

float3 srgb_to_linear(float3 c) { return pow(max(c, 0.0), 2.2); }
float4 srgb_to_linear(float4 c) { return float4(pow(max(c.xyz, 0.0), 2.2), c.w); }
float3 linear_to_srgb(float3 c) { return pow(max(c, 0.0), 1.0 / 2.2); }
float4 linear_to_srgb(float4 c) { return float4(pow(max(c.xyz, 0.0), 1.0 / 2.2), c.w); }

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
	float emissiveAnimStrength, float emissiveAnimScale)
{
	float strength = saturate(emissiveAnimStrength) * saturate(mask);
	float scale = max(emissiveAnimScale, 0.1);
	float2 gridUv = uv * scale * 2.2;
	float2 cell = floor(gridUv);
	float2 local = frac(gridUv) - 0.5;
	float cellSeed  = hash12(cell + float2(19.1, 73.7));
	float cellPhase = hash12(cell + float2(11.7, 5.3)) * 6.2831853;
	float cellSpeed = lerp(0.30, 1.35, hash12(cell + float2(37.2, 29.8)));
	float slowPulse = 0.5 + 0.5 * sin(t * cellSpeed + cellPhase);
	float drift   = smooth_rand_1d(t * (0.24 + cellSpeed * 0.18) + cellPhase, 91.0 + cellSeed * 211.0);
	float flicker = smooth_rand_1d(t * (0.75 + cellSpeed * 0.55) + cellPhase * 1.7, 173.0 + cellSeed * 307.0);
	float cellCore = smoothstep(0.72, 0.06, length(local));
	float mod = slowPulse * 0.58 + drift * 0.27 + flicker * 0.15;
	float anim = saturate(lerp(0.42, 1.36, mod) * lerp(0.88, 1.10, cellCore));
	return lerp(1.0, anim, strength);
}

void terrain_fragment(
	in float4 vColor : COLOR0,
#if defined (VERTEX_LIGHTING)
	in float3 vLightResult : COLOR1,
#if defined(SPECULAR_ENABLED) || defined(SPECULARMAP_ENABLED)
	in float3 vSpecularResult : COLOR2,
#endif
#endif
	in float2 vTexCoord : TEXCOORD0,
#if !defined(VERTEX_LIGHTING)
	in float3 vViewNormal : TEXCOORD2,
#if defined(NORMALMAP_ENABLED) && defined(VERTEX_TANGENTS)
	in float3 vViewTangent : TEXCOORD3,
#endif
	in float3 vViewPosition : TEXCOORD4,
#endif
	in float vDepth : TEXCOORD5,
#if defined(SHADOWRECEIVER)
	in float4 vLightSpacePos1 : TEXCOORD6,
#if defined(PSSM_ENABLED)
	in float4 vLightSpacePos2 : TEXCOORD7,
	in float4 vLightSpacePos3 : TEXCOORD8,
#endif
#endif

	// Uniforms (Must match program file list to avoid binder errors)
	uniform float4 sceneAmbient,
	uniform float baseTime,
	uniform float emissiveAnimStrength,
	uniform float emissiveAnimSpeed,
	uniform float emissiveAnimScale,
	uniform float objectAmbientStrength,
	uniform float terrainDiffuseBoost,
	uniform float4 fogColour,
	uniform float4 fogParams,
	// Always declared so the material can safely set it for all quality levels.
	// Only actively used for specular calculations when SPECULAR_ENABLED is defined.
	uniform float materialShininess,

#if defined(DETAILMAP_ENABLED)
	uniform sampler2D detailMap : register(s1),
	uniform sampler2D detailNormalMap : register(s7),
#endif

#if defined(NORMALMAP_ENABLED)
	uniform sampler2D normalMap : register(s2),
#endif
#if defined(SPECULARMAP_ENABLED)
	uniform sampler2D specularMap : register(s3),
#endif
#if defined(EMISSIVEMAP_ENABLED)
	uniform sampler2D emissiveMap : register(s4),
#endif
	uniform sampler2D glossMap : register(s5),
	uniform sampler2D metallicMap : register(s6),

#if defined(SHADOWRECEIVER)
	uniform sampler2D shadowMap1 : register(s8),
#if defined(PSSM_ENABLED)
	uniform sampler2D shadowMap2 : register(s9),
	uniform sampler2D shadowMap3 : register(s10),
#endif
#endif

	uniform float glossStrength,
	uniform float glossBias,
	uniform float metallicStrength,
	uniform float metallicBias,
	uniform float rimStrength,
	uniform float rimPower,
	uniform float tileBlendStrength,
	uniform float detailNormalStrength,
	uniform float terrainNormalStrength,
	uniform float detailContrastStrength,
	uniform float detailFadeStart,
	uniform float detailFadeRange,
	uniform float slopeDetailStrength,
	uniform float specAAStrength,
	uniform float wrapDiffuse,

#if defined(SHADOWRECEIVER)
	uniform float4 invShadowMapSize1,
#if defined(PSSM_ENABLED)
	uniform float4 invShadowMapSize2,
	uniform float4 invShadowMapSize3,
	uniform float4 pssmSplitPoints,
#endif
#endif

#if !defined(VERTEX_LIGHTING)
#if defined(SPECULAR_ENABLED) || defined(SPECULARMAP_ENABLED)
	// (materialShininess declared above, unconditionally)
#endif
	uniform float4 lightDiffuse[MAX_LIGHTS],
	uniform float4 lightPosition[MAX_LIGHTS],
#if defined(SPECULAR_ENABLED) || defined(SPECULARMAP_ENABLED)
	uniform float4 lightSpecular[MAX_LIGHTS],
#endif
	uniform float4 lightAttenuation[MAX_LIGHTS],
	uniform float4 spotLightParams[MAX_LIGHTS],
	uniform float4 lightDirection[MAX_LIGHTS],
#if MAX_LIGHTS > 1
	uniform float lightCount,
#endif
#endif

	out float4 oColor : COLOR0
#if defined(LOGDEPTH_ENABLE)
	, out float oDepth : DEPTH
#endif
) {
	// Dummy sum to prevent the compiler from optimizing unused uniforms away, which triggers the same binder exception
	// objectAmbientStrength must appear in the dummy sum so DX9/SM3 doesn't strip it from the constant table.
	float paramDummy = (objectAmbientStrength + tileBlendStrength + detailNormalStrength + terrainNormalStrength + detailContrastStrength + detailFadeStart + detailFadeRange + slopeDetailStrength + specAAStrength + wrapDiffuse) * 1e-6;
#if defined(SHADOWRECEIVER)
	paramDummy += invShadowMapSize1.x * 1e-6;
#if defined(PSSM_ENABLED)
	paramDummy += (invShadowMapSize2.x + invShadowMapSize3.x + pssmSplitPoints.x) * 1e-6;
#endif
#endif

	// 1. Basic Texture Sampling
	float4 diffuseTex = srgb_to_linear(tex2D(diffuseMap, vTexCoord));
	
#if defined(SPECULARMAP_ENABLED)
	float3 specularTex = srgb_to_linear(tex2D(specularMap, vTexCoord).xyz);
#else
	float3 specularTex = float3(1.0, 1.0, 1.0);
#endif

#if defined(EMISSIVEMAP_ENABLED)
	float3 emissiveTex = srgb_to_linear(tex2D(emissiveMap, vTexCoord).xyz);
	float emissiveMask = saturate(dot(emissiveTex, float3(0.299, 0.587, 0.114)) * 3.2);
	float emissiveAnim = emissive_anim_factor(vTexCoord, baseTime * 6.2831853 * emissiveAnimSpeed, emissiveMask, emissiveAnimStrength, emissiveAnimScale);
	emissiveTex *= emissiveAnim;
#else
	float3 emissiveTex = float3(0.0, 0.0, 0.0);
#endif

	float glossTex = tex2D(glossMap, vTexCoord).x;
	float metallicTex = tex2D(metallicMap, vTexCoord).x;

	// Derived Gloss/Metallic
	float specLuma = dot(specularTex, float3(0.299, 0.587, 0.114));
	float emissiveLuma = dot(emissiveTex, float3(0.299, 0.587, 0.114));
	float derivedGloss = saturate(specLuma * 0.50 + emissiveLuma * 0.15);
	float derivedMetallic = saturate(specLuma * 0.45 - emissiveLuma * 0.08);
	float gloss = saturate(max(derivedGloss, glossTex) * glossStrength + glossBias);
	float metallic = saturate(max(derivedMetallic, metallicTex) * metallicStrength + metallicBias);
	float specScale = lerp(0.72, 1.52, gloss);
	float metallicSpecScale = lerp(0.95, 1.48, metallic);
	
	// 2. Basic Lighting
#if defined(VERTEX_LIGHTING)

	float3 lightResult = vLightResult + srgb_to_linear(sceneAmbient.xyz);
#if defined(SPECULAR_ENABLED) || defined(SPECULARMAP_ENABLED)
	float3 specularResult = vSpecularResult;
#endif

#else

	float3 viewPos = vViewPosition;
	float3 viewNormal;

#if defined(NORMALMAP_ENABLED)
	// tangent basis
#if defined(VERTEX_TANGENTS)
	float3 binormal = cross(vViewTangent, vViewNormal);
	float3x3 tbn = float3x3(vViewTangent, binormal, vViewNormal);
#else
	float3x3 tbn = cotangent_frame(normalize(vViewNormal), viewPos, vTexCoord);
#endif

	// per-pixel view normal
	float3 normalTex = tex2D(normalMap, vTexCoord).xyz * 2.0 - 1.0;
#if defined(DETAILMAP_ENABLED)
	float2 detailUv = frac(vTexCoord * 8.0);
	float2 detailNormalXY = tex2D(detailNormalMap, detailUv).xy * 2.0 - 1.0;
	normalTex.xy += detailNormalXY * (2.5 * saturate(tileBlendStrength + 0.35) * detailNormalStrength);
#endif
	// DX9 lacks IBL fill-light, so reduce normal bend to avoid pitch-black slope shadows
	normalTex.xy *= (2.15 * terrainNormalStrength);
	
	// Clamp XY magnitude to slightly less than 1.0 to ensure Z is always > 0
	float xySq = dot(normalTex.xy, normalTex.xy);
	if (xySq > 0.99)
	{
		normalTex.xy *= rsqrt(xySq) * 0.995;
	}
	
	normalTex.z = sqrt(saturate(1.0 - dot(normalTex.xy, normalTex.xy)));
	viewNormal = normalize(mul(normalTex, tbn));
#else
	// per-pixel view normal
	viewNormal = normalize(vViewNormal);
#endif

	float3 viewDir = normalize(-viewPos);
	float viewFacing = saturate(dot(viewNormal, viewDir));

#if defined(SPECULAR_ENABLED) || defined(SPECULARMAP_ENABLED)
	float3 viewReflect = reflect(normalize(viewPos), viewNormal);
#endif

	float3 lightResult = srgb_to_linear(sceneAmbient.xyz);
#if defined(SPECULAR_ENABLED) || defined(SPECULARMAP_ENABLED)
	float3 specularResult = float3(0.0, 0.0, 0.0);
#endif

	float shadow = 1.0;
#if defined(SHADOWRECEIVER)
#if defined(PSSM_ENABLED)
	if (vDepth <= pssmSplitPoints.y)
	{
		shadow = PCF_Filter(shadowMap1, vLightSpacePos1, invShadowMapSize1);
	}
	else if (vDepth <= pssmSplitPoints.z)
	{
		shadow = PCF_Filter(shadowMap2, vLightSpacePos2, invShadowMapSize2);
	}
	else
	{
		shadow = PCF_Filter(shadowMap3, vLightSpacePos3, invShadowMapSize3);
	}
#else
	shadow = PCF_Filter(shadowMap1, vLightSpacePos1, invShadowMapSize1);
#endif
	shadow = shadow * 0.7 + 0.3;
#endif

#if MAX_LIGHTS > 1
	// for each possible light source...
	for (int i = 0; i < MAX_LIGHTS; ++i)
	{
		if (i >= int(lightCount))
			break;
#else
	{
		const int i = 0;
#endif
		// get the direction from the pixel to the light source
		float3 pixelToLight = lightPosition[i].xyz - (viewPos * lightPosition[i].w);
		float d = length(pixelToLight);
		pixelToLight /= d;
		
		// compute distance attentuation
		float attenuation = saturate(1.0 / 
			(lightAttenuation[i].y + d * (lightAttenuation[i].z + d * lightAttenuation[i].w)));

		// compute spotlight attenuation
		float spotLinearFalloff = saturate((dot(pixelToLight, -lightDirection[i].xyz) - spotLightParams[i].y) / (spotLightParams[i].x - spotLightParams[i].y));
		attenuation *= pow(smoothstep(0.0, 1.0, spotLinearFalloff), spotLightParams[i].z);

		if (i == 0)
		{
			attenuation *= shadow;
		}

		// accumulate diffuse lighting
		float NdotL = dot(viewNormal, pixelToLight);
		// Force minimum wrap in DX9 since we lack SM4's ambient IBL fill-lighting
		float effWrap = max(wrapDiffuse, 0.15);
		float wrappedNdotL = saturate((NdotL + effWrap) / max(1.0 + effWrap, 1e-3));
		float attenDiff = attenuation * wrappedNdotL;
		
		lightResult += srgb_to_linear(lightDiffuse[i].xyz) * attenDiff;

#if defined(SPECULAR_ENABLED) || defined(SPECULARMAP_ENABLED)
		// accumulate specular lighting
		float3 halfVec = normalize(pixelToLight + viewDir);
		float specNdotH = saturate(dot(viewNormal, halfVec));
		float specPower = max(materialShininess * max(1.0, 0.2) * lerp(0.65, 1.80, gloss), 1.0);
		float normalization = (specPower + 2.0) / 8.0;
		float attenSpec = attenuation * normalization * pow(specNdotH, specPower);
		specularResult += srgb_to_linear(lightSpecular[i].xyz) * attenSpec * max(dot(viewNormal, pixelToLight), 0.0);
#endif
	}

	float fresnelTerm = pow(1.0 - viewFacing, 5.0);
	float3 dielectricF0 = float3(0.035, 0.035, 0.035);
	float3 baseF0 = lerp(dielectricF0, saturate(lerp(diffuseTex.xyz, specularTex, 0.65)), metallic);
	float3 fresnelColor = baseF0 + (1.0 - baseF0) * fresnelTerm;
	float rimTerm = pow(1.0 - viewFacing, max(rimPower, 0.01)) * rimStrength;
#endif

	// 3. Simple Result
	// Reduced diffuse boost for DX9 since wrapped lighting already brightens it
	const float kTerrainDiffuseBoost = 1.16;
#if !defined(VERTEX_LIGHTING)
	float3 diffuseEnergy = saturate((1.0 - fresnelColor) * lerp(1.0, 0.60, metallic));
	diffuseEnergy = max(diffuseEnergy, float3(0.20, 0.20, 0.20));
	
	oColor.xyz = diffuseTex.xyz * lightResult * srgb_to_linear(vColor.xyz) * (kTerrainDiffuseBoost * terrainDiffuseBoost) * lerp(1.0, 0.92, metallic);
	oColor.xyz += diffuseTex.xyz * rimTerm * 0.16;
#else
	oColor.xyz = diffuseTex.xyz * lightResult * srgb_to_linear(vColor.xyz) * (kTerrainDiffuseBoost * terrainDiffuseBoost);
#endif
	
#if defined(SPECULAR_ENABLED) || defined(SPECULARMAP_ENABLED)
#if !defined(VERTEX_LIGHTING)
	oColor.xyz += specularResult * specularTex * specScale * metallicSpecScale * fresnelColor;
#else
	oColor.xyz += specularResult * specularTex * specScale * metallicSpecScale;
#endif
#endif

#if defined(EMISSIVEMAP_ENABLED)
	oColor.xyz += emissiveTex;
#endif

#if defined(DETAILMAP_ENABLED)
	float3 detailTex = tex2D(detailMap, frac(vTexCoord * 8.0)).xyz;
	float3 detailContrast = lerp(float3(1.0, 1.0, 1.0), detailTex * 2.0, saturate(0.65 * detailContrastStrength));
	float detailDistance = saturate((vDepth - detailFadeStart) / max(detailFadeRange, 1e-3));
	float3 detailColor = lerp(detailContrast, float3(1.0, 1.0, 1.0), detailDistance);
	float seamMask = smoothstep(0.2, 0.8, diffuseTex.a);
	
	float slopeMask = 1.0;
	float detailBlendMask = lerp(seamMask, 0.5, saturate(tileBlendStrength));
	// slope limits exist in SM4, omitted here for simplicity
	oColor.xyz = lerp(oColor.xyz, oColor.xyz * detailColor, detailBlendMask);
#endif

	// Keep low-impact parameter references in the final color so DX9 does not strip them
	// from the constant table before OGRE binds material constants.
	oColor.xyz *= (1.0 + (materialShininess + gloss + metallic + glossStrength + glossBias + metallicStrength + metallicBias + tileBlendStrength + detailNormalStrength + terrainNormalStrength + terrainDiffuseBoost + detailContrastStrength + detailFadeStart + detailFadeRange + slopeDetailStrength + specAAStrength + wrapDiffuse + rimStrength + rimPower + emissiveAnimStrength + emissiveAnimSpeed + emissiveAnimScale) * 1e-6 + paramDummy);

	const float kExposure = 1.30;
	float3 exposedColor = oColor.xyz * kExposure;
	oColor.xyz = lerp(exposedColor, subtle_tonemap(exposedColor), 0.40);

	oColor.a = vColor.a;
	
	// 4. Fog
	float fogValue = saturate((vDepth - fogParams.y) * fogParams.w);
	oColor.xyz = lerp(oColor.xyz, srgb_to_linear(fogColour.xyz), fogValue);

	oColor.xyz = linear_to_srgb(oColor.xyz);

#if defined(LOGDEPTH_ENABLE)
	// Match the stock terrain depth path so terrain and base passes compare consistently.
	const float C = 0.1;
	const float far = 1e+09;
	const float offset = 1.0;
	oDepth = log(C * vDepth + offset) / log(C * far + offset);
#endif
}

// -------------------------------------------

void terrain_vertex(
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

	in float4 iPosition : POSITION0,
	in uint4 iBlendIndices : BLENDINDICES,
#if !defined(VERTEX_LIGHTING) && defined(NORMALMAP_ENABLED) && defined(VERTEX_TANGENTS)
	in float3 iTangent : TANGENT0,
#endif
	in float4 iColor : COLOR0,
	in float heightOffset : TEXCOORD1,

	out float4 vColor : COLOR0,
#if defined (VERTEX_LIGHTING)
	out float3 vLightResult : COLOR1,
#if defined(SPECULAR_ENABLED) || defined(SPECULARMAP_ENABLED)
	out float3 vSpecularResult : COLOR2,
#endif
#endif
	out float2 vTexCoord : TEXCOORD0,
#if !defined(VERTEX_LIGHTING)
	out float3 vViewNormal : TEXCOORD2,
#if defined(NORMALMAP_ENABLED) && defined(VERTEX_TANGENTS)
	out float3 vViewTangent : TEXCOORD3,
#endif
	out float3 vViewPosition : TEXCOORD4,
#endif
	out float vDepth : TEXCOORD5,
#if defined(SHADOWRECEIVER)
	out float4 vLightSpacePos1 : TEXCOORD6,
#if defined(PSSM_ENABLED)
	out float4 vLightSpacePos2 : TEXCOORD7,
	out float4 vLightSpacePos3 : TEXCOORD8,
#endif
#endif

	out float4 oPosition : POSITION
)
{
	iPosition.y = heightOffset;
	float2 nNormal = (float2(iBlendIndices.zw) - float2(127.0, 127.0)) / float2(127.0, 127.0);
	float3 iNormal = float3(nNormal.x, sqrt(saturate(1.0 - nNormal.x*nNormal.x - nNormal.y*nNormal.y)), nNormal.y);

	oPosition = mul(wvpMat, iPosition);
	// Sample atlas texels at center to avoid orientation-dependent half-texel distortion.
	vTexCoord = (float2(iBlendIndices.xy) + 0.5) / 160.0;

#if defined(VERTEX_LIGHTING)
	float3 vViewPosition, vViewNormal;
#endif
	vViewPosition = mul(worldViewMat, float4(iPosition.xyz, 1.0)).xyz;
	vViewNormal = mul(worldViewMat, float4(iNormal.xyz, 0.0)).xyz;
#if !defined(VERTEX_LIGHTING) && defined(NORMALMAP_ENABLED) && defined(VERTEX_TANGENTS)
	vViewTangent = mul(worldViewMat, float4(iTangent.xyz, 0.0)).xyz;
#endif

	vDepth = oPosition.z;
	vColor = iColor;
	
#if defined(SHADOWRECEIVER)
	// calculate vertex position in light space
	vLightSpacePos1 = mul(texWorldViewProj1, iPosition);
#if defined(PSSM_ENABLED)
	vLightSpacePos2 = mul(texWorldViewProj2, iPosition);
	vLightSpacePos3 = mul(texWorldViewProj3, iPosition);
#endif
#endif

#if defined(VERTEX_LIGHTING)
	// assume light 0 is the sun directional light
	// get the direction from the pixel to the light source
	float3 pixelToLight = normalize(lightPosition[0].xyz - (vViewPosition * lightPosition[0].w));
	
	// accumulate diffuse lighting
	float attenuation = max(dot(vViewNormal, pixelToLight.xyz), 0.0);
	vLightResult = srgb_to_linear(lightDiffuse[0].xyz) * attenuation;

#if defined(SPECULAR_ENABLED) || defined(SPECULARMAP_ENABLED)
	// per-pixel view reflection
	float3 viewReflect = reflect(normalize(vViewPosition), vViewNormal);

	// accumulate specular lighting
	attenuation *= pow(max(dot(viewReflect, pixelToLight), 0.0), materialShininess);
	vSpecularResult = srgb_to_linear(lightSpecular[0].xyz) * attenuation;
#endif
#endif
}
