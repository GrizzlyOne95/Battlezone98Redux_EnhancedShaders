#if defined(SHADOWRECEIVER)
float PCF_Filter(in Texture2D map,
					in SamplerState sam,
					in float4 uv,
					in float2 invMapSize)
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
		{
			[unroll] for (int x = 0; x < PCF_SIZE; ++x)
			{
				int i = y * PCF_SIZE + x;
				kernel[i] = step(uv.z, map.Sample(sam, (c + float2(x, y)) * invMapSize).x);
			}
		}
	}

	float4 sum = float4(0.0, 0.0, 0.0, 0.0);
	{
		[unroll] for (int y = 0; y < PCF_SIZE - 1; ++y)
		{
			[unroll] for (int x = 0; x < PCF_SIZE - 1; ++x)
			{
				int i = y * PCF_SIZE + x;
				sum += float4(kernel[i], kernel[i + 1], kernel[i + PCF_SIZE], kernel[i + PCF_SIZE + 1]);
			}
		}
	}

	return lerp(lerp(sum.x, sum.y, f.x), lerp(sum.z, sum.w, f.x), f.y) / float((PCF_SIZE-1)*(PCF_SIZE-1));
#else
	return step(uv.z, map.Sample(sam, uv.xy).x);
#endif
}
#endif

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

// -------------------------------------------
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

	out float4 oPosition : SV_POSITION
)
{
	iPosition.y = heightOffset;
	float2 nNormal = (float2(iBlendIndices.zw) - float2(127.0, 127.0)) / float2(127.0, 127.0);
	float3 iNormal = float3(nNormal.x, sqrt(1.0 - nNormal.x*nNormal.x - nNormal.y*nNormal.y), nNormal.y);

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
	vColor = iColor.bgra;
	
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

// -------------------------------------------

void terrain_fragment(
	uniform Texture2D diffuseMap : register(t0),
	uniform SamplerState diffuseSam : register(s0),
#if defined(DETAILMAP_ENABLED)
	uniform Texture2D detailMap : register(t1),
	uniform SamplerState detailSam : register(s1),
#endif
#if !defined(SHADOWRECEIVER)
	uniform Texture2D detailNormalMap : register(t7),
	uniform SamplerState detailNormalSam : register(s7),
#elif defined(PSSM_ENABLED)
	uniform Texture2D detailNormalMap : register(t10),
	uniform SamplerState detailNormalSam : register(s10),
#else
	uniform Texture2D detailNormalMap : register(t8),
	uniform SamplerState detailNormalSam : register(s8),
#endif
#if defined(NORMALMAP_ENABLED)
	uniform Texture2D normalMap : register(t2),
	uniform SamplerState normalSam : register(s2),
#endif
#if defined(SPECULARMAP_ENABLED)
	uniform Texture2D specularMap : register(t3),
	uniform SamplerState specularSam : register(s3),
#endif
#if defined(EMISSIVEMAP_ENABLED)
	uniform Texture2D emissiveMap : register(t4),
	uniform SamplerState emissiveSam : register(s4),
#endif
	uniform Texture2D glossMap : register(t5),
	uniform SamplerState glossSam : register(s5),
	uniform Texture2D metallicMap : register(t6),
	uniform SamplerState metallicSam : register(s6),
#if defined(SHADOWRECEIVER)
	uniform Texture2D shadowMap1 : register(t7),
	uniform SamplerState shadowSam1 : register(s7),
#if defined(PSSM_ENABLED)
	uniform Texture2D shadowMap2 : register(t8),
	uniform SamplerState shadowSam2 : register(s8),
	uniform Texture2D shadowMap3 : register(t9),
	uniform SamplerState shadowSam3 : register(s9),
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
#if defined(SPECULAR_ENABLED) || defined(SPECULARMAP_ENABLED)
	uniform float materialShininess,
#endif
	uniform float4 lightDiffuse[MAX_LIGHTS],
	uniform float4 lightPosition[MAX_LIGHTS],
	uniform float4 lightSpecular[MAX_LIGHTS],
	uniform float4 lightAttenuation[MAX_LIGHTS],
	uniform float4 spotLightParams[MAX_LIGHTS],
	uniform float4 lightDirection[MAX_LIGHTS],
	uniform float lightCount,
#endif

	uniform float4 fogColour,
	uniform float4 fogParams,
	uniform float tileBlendStrength,
	uniform float detailNormalStrength,
	uniform float glossStrength,
	uniform float glossBias,
	uniform float metallicStrength,
	uniform float metallicBias,
	uniform float objectAmbientStrength,
	uniform float terrainNormalStrength,
	uniform float terrainDiffuseBoost,
	uniform float detailContrastStrength,
	uniform float detailFadeStart,
	uniform float detailFadeRange,
	uniform float slopeDetailStrength,
	uniform float specAAStrength,
	uniform float wrapDiffuse,
	uniform float rimStrength,
	uniform float rimPower,

	in float4 vColor : COLOR0,
	uniform float4x4 viewMat,
#if defined(VERTEX_LIGHTING)
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

	out float4 oColor : SV_TARGET
#if defined(LOGDEPTH_ENABLE)	
	, out float oDepth : SV_DEPTH
#endif
)
{
	const float kTerrainNormalStrength = 2.6;
	const float kDetailNormalStrength = 2.2;
	const float kTerrainDiffuseBoost = 1.12;
	const float kAOPower = 1.30;
	const float kAOStrength = 0.0;
	const float kIBLDiffuseStrength = 0.44;
	const float kIBLSpecStrength = 0.05;
	const float kExposure = 1.14;

#if defined(SHADOWRECEIVER)
	// shadow texture
	float shadow;
#if defined(PSSM_ENABLED)
	if (vDepth <= pssmSplitPoints.y)
	{
#endif
		shadow = PCF_Filter(shadowMap1, shadowSam1, vLightSpacePos1, invShadowMapSize1.xy);
#if defined(PSSM_ENABLED)
	}
	else if (vDepth <= pssmSplitPoints.z)
	{
		shadow = PCF_Filter(shadowMap2, shadowSam2, vLightSpacePos2, invShadowMapSize2.xy);
	}
	else
	{
		shadow = PCF_Filter(shadowMap3, shadowSam3, vLightSpacePos3, invShadowMapSize3.xy);
	}
#endif
	shadow = shadow * 0.7 + 0.3;
#endif

#if defined(VERTEX_LIGHTING)

	// combine ambient and shadowed light result
	float3 lightResult = vLightResult;
#if defined(SHADOWRECEIVER)
	lightResult *= shadow;
#endif
	lightResult += srgb_to_linear(sceneAmbient.xyz);

#if defined(SPECULAR_ENABLED) || defined(SPECULARMAP_ENABLED)
	float3 specularResult = vSpecularResult;
#endif
	
#else

	// per-pixel view position
	float3 viewPos = vViewPosition;
	float3 viewNormal;

#if defined(NORMALMAP_ENABLED)
	// tangent basis
#if defined(VERTEX_TANGENTS)
	float3 binormal = cross(vViewTangent, vViewNormal);
	float3x3 tbn = float3x3(vViewTangent, binormal, vViewNormal);
#else
	float3x3 tbn = cotangent_frame(vViewNormal, vViewPosition.xyz, vTexCoord);
#endif

	// per-pixel view normal
	float3 normalTex = normalMap.Sample(normalSam, vTexCoord).xyz * 2.0 - 1.0;
#if defined(DETAILMAP_ENABLED)
	float2 detailUv = frac(vTexCoord * 8.0);
	float2 detailNormalXY = detailNormalMap.Sample(detailNormalSam, detailUv).xy * 2.0 - 1.0;
	normalTex.xy += detailNormalXY * (kDetailNormalStrength * saturate(tileBlendStrength + 0.35) * detailNormalStrength);
#endif
	normalTex.xy *= (kTerrainNormalStrength * terrainNormalStrength);
	normalTex.z = sqrt(saturate(1.0 - dot(normalTex.xy, normalTex.xy)));
	viewNormal = normalize(mul(normalTex, tbn));
#else
	// per-pixel view normal
	viewNormal = normalize(vViewNormal);
#endif

	float3 viewDir = normalize(-viewPos);
	float viewFacing = saturate(dot(viewNormal, viewDir));
	float specAAFactor = 1.0;
#if defined(SPECULAR_ENABLED) || defined(SPECULARMAP_ENABLED)
	float3 dndx = ddx(viewNormal);
	float3 dndy = ddy(viewNormal);
	float normalVariance = saturate((dot(dndx, dndx) + dot(dndy, dndy)) * 0.5);
	specAAFactor = rcp(1.0 + normalVariance * specAAStrength * 8.0);
#endif

	// start with ambient light and no specular
	float3 lightResult = srgb_to_linear(sceneAmbient.xyz);
#if defined(SPECULAR_ENABLED) || defined(SPECULARMAP_ENABLED)
	float3 specularResult = float3(0,0,0);
#endif

#if defined(SPECULAR_ENABLED) || defined(SPECULARMAP_ENABLED)
	// per-pixel view reflection
	float3 viewReflect = reflect(normalize(viewPos), viewNormal);
	
	float roughness = saturate(sqrt(2.0 / (materialShininess + 2.0)));
	float3 f0 = float3(0.04, 0.04, 0.04);
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
			// it's much faster to just do the math than have a branch on low-end GPUs
			// non-spotlights have falloff power 0 which yields a constant output
			attenuation *= pow(clamp(
				(dot(pixelToLight, -lightDirection[i].xyz) - spotLightParams[i].y) /
				(spotLightParams[i].x - spotLightParams[i].y), 1e-30, 1.0), spotLightParams[i].z);

#if defined(SHADOWRECEIVER)
			// apply shadow attenuation
			attenuation *= shadow;
#endif
            float baseAttenuation = attenuation;

			// accumulate diffuse lighting
			float NdotL = saturate(dot(viewNormal, pixelToLight));
			float wrappedNdotL = saturate((NdotL + wrapDiffuse) / max(1.0 + wrapDiffuse, 1e-3));
			lightResult.xyz += srgb_to_linear(lightDiffuse[i].xyz) * baseAttenuation * wrappedNdotL;

#if defined(SPECULAR_ENABLED) || defined(SPECULARMAP_ENABLED)
			// accumulate GGX specular lighting
			float3 halfVec = normalize(pixelToLight + viewDir);
			float NdotH = saturate(dot(viewNormal, halfVec));
			float NdotV = saturate(dot(viewNormal, viewDir));
			
			float D = D_GGX(NdotH, roughness);
			float G = G_SchlickGGX(NdotV, NdotL, roughness);
			float3 F = F_Schlick(saturate(dot(halfVec, viewDir)), f0);
			
			float3 specularTerm = (D * G * F) / max(4.0 * NdotL * NdotV, 0.001);
			specularResult.xyz += srgb_to_linear(lightSpecular[i].xyz) * baseAttenuation * specularTerm * max(NdotL, 0.0) * specAAFactor;
#endif
	}

#endif

	// diffuse texture
	float4 diffuseTex = srgb_to_linear(diffuseMap.Sample(diffuseSam, vTexCoord));
	float seamSoft = saturate(tileBlendStrength * 0.8);
	float3 diffuseLow = diffuseMap.SampleBias(diffuseSam, vTexCoord, 1.0).xyz;
	float3 seamReducedDiffuse = lerp(diffuseTex.xyz, diffuseLow, seamSoft * 0.25);
	oColor.xyz = lightResult.xyz * vColor.xyz * seamReducedDiffuse * (kTerrainDiffuseBoost * terrainDiffuseBoost);

#if defined(SPECULARMAP_ENABLED)
	// specular texture
	float3 specularTex = srgb_to_linear(specularMap.Sample(specularSam, vTexCoord).xyz);
#else
	float3 specularTex = float3(1, 1, 1);
#endif

#if defined(EMISSIVEMAP_ENABLED)
	// emissive texture
	float3 emissiveTex = srgb_to_linear(emissiveMap.Sample(emissiveSam, vTexCoord).xyz);
#else
	float3 emissiveTex = float3(0, 0, 0);
#endif
	float glossTex = glossMap.Sample(glossSam, vTexCoord).x;
	float metallicTex = metallicMap.Sample(metallicSam, vTexCoord).x;
	float specLuma = dot(specularTex, float3(0.299, 0.587, 0.114));
	float emissiveLuma = dot(emissiveTex, float3(0.299, 0.587, 0.114));
	float derivedGloss = saturate(specLuma * 1.10 + emissiveLuma * 0.15);
	float derivedMetallic = saturate(specLuma * 1.20 - emissiveLuma * 0.10);
	float gloss = saturate(max(derivedGloss, glossTex) * glossStrength + glossBias);
	float metallic = saturate(max(derivedMetallic, metallicTex) * metallicStrength + metallicBias);
	float specScale = lerp(0.80, 1.60, gloss);
	float metallicSpecScale = lerp(0.90, 1.30, metallic);
	float fresnelTerm = 0.0;
	float3 fresnelColor = float3(1.0, 1.0, 1.0);
	float rimTerm = 0.0;
#if defined(VERTEX_LIGHTING) || (!defined(SPECULAR_ENABLED) && !defined(SPECULARMAP_ENABLED))
	float l_materialShininess = 32.0;
#else
	float l_materialShininess = materialShininess;
#endif
	float roughness = saturate(sqrt(2.0 / (max(l_materialShininess, 0.0) + 2.0)));
#if !defined(VERTEX_LIGHTING)
	float3 dielectricF0 = float3(0.04, 0.04, 0.04);
	float3 baseF0 = lerp(dielectricF0, saturate(seamReducedDiffuse), metallic);
	fresnelTerm = pow(1.0 - viewFacing, 5.0);
	fresnelColor = baseF0 + (1.0 - baseF0) * fresnelTerm;
	rimTerm = pow(1.0 - viewFacing, max(rimPower, 0.01)) * rimStrength;
#endif
	float ao = lerp(1.0, pow(saturate(diffuseTex.a), kAOPower), kAOStrength);
	float3 diffuseEnergy = saturate((1.0 - fresnelColor) * lerp(1.0, 0.60, metallic));
	diffuseEnergy = max(diffuseEnergy, 0.20.xxx);
	
	oColor.xyz *= lerp(1.0, 0.92, metallic);
	oColor.xyz *= ao; // Apply AO to main lighting
	oColor.xyz += seamReducedDiffuse * rimTerm * 0.16;

	// IBL / Ambient Boost
	float3 iblDiffuse = srgb_to_linear(sceneAmbient.xyz) * seamReducedDiffuse * diffuseEnergy * (kIBLDiffuseStrength * ao);
	float3 iblSky = srgb_to_linear(sceneAmbient.xyz) * 0.90;
	float3 iblSpec = iblSky * fresnelColor * lerp(0.18, 0.95, 1.0 - roughness) * (kIBLSpecStrength * ao);
	oColor.xyz += iblDiffuse + iblSpec * specularTex;
	float shininessDummy = 0.0;
#if defined(SPECULAR_ENABLED) || defined(SPECULARMAP_ENABLED)
	shininessDummy = materialShininess;
#endif
	// Keep gloss uniforms active for low-feature permutations where specular is compiled out.
	oColor.xyz *= (1.0 + (gloss + metallic + shininessDummy + glossStrength + glossBias + metallicStrength + metallicBias + detailNormalStrength + terrainNormalStrength + terrainDiffuseBoost + detailContrastStrength + detailFadeStart + detailFadeRange + slopeDetailStrength + specAAStrength + wrapDiffuse + rimStrength + rimPower) * 1e-6);

#if defined(SPECULAR_ENABLED) || defined(SPECULARMAP_ENABLED)
	oColor.xyz += specularResult.xyz * specularTex.xyz * specScale * metallicSpecScale * fresnelColor;
#endif

#if defined(EMISSIVEMAP_ENABLED)
	oColor.xyz += emissiveTex.xyz;
#endif

#if defined(DETAILMAP_ENABLED)
	// detail texture
	float3 detailTex = detailMap.Sample(detailSam, frac(vTexCoord * 8)).xyz;
	float3 detailContrast = lerp(float3(1, 1, 1), detailTex * 2.0, saturate(0.7 * detailContrastStrength));
	float detailDistance = saturate((vDepth - detailFadeStart) / max(detailFadeRange, 1e-3));
	float3 detailColor = lerp(detailContrast, float3(1, 1, 1), detailDistance);
	float seamMask = smoothstep(0.2, 0.8, diffuseTex.a);
	float slopeMask = 1.0;
#if !defined(VERTEX_LIGHTING)
	float3 geomNormal = normalize(cross(ddx(viewPos), ddy(viewPos)));
	slopeMask = saturate(1.0 - abs(geomNormal.y));
#endif
	float detailBlendMask = lerp(seamMask, 0.5, saturate(tileBlendStrength));
	detailBlendMask *= lerp(1.0, slopeMask, saturate(slopeDetailStrength));
	oColor.xyz = lerp(oColor.xyz, oColor.xyz * detailColor, detailBlendMask);
#endif

	oColor.xyz = min(oColor.xyz, 3.0);
	float3 exposedColor = oColor.xyz * kExposure;
	oColor.xyz = lerp(exposedColor, subtle_tonemap(exposedColor), 0.55);
	
	// fog
	float fogValue = saturate((vDepth - fogParams.y) * fogParams.w);
	oColor.xyz = lerp(oColor.xyz, srgb_to_linear(fogColour.xyz), fogValue);

	// Convert back to sRGB display format
	oColor.xyz = linear_to_srgb(oColor.xyz);

	// output alpha
	oColor.a = vColor.a;

#if defined(LOGDEPTH_ENABLE)
	// logarithmic depth
	const float C = 0.1;
	const float far = 1e+09;
	const float offset = 1.0;
	oDepth = log(C * vDepth + offset) / log(C * far + offset);
#endif
}
