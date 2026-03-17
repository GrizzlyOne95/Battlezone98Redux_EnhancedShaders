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

float3 safe_normalize(float3 v)
{
	float lenSq = dot(v, v);
	return (lenSq > 1e-8) ? v * rsqrt(lenSq) : float3(0.0, 0.0, 0.0);
}

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

	in float4 iPosition : POSITION,
	in float2 iTexCoord : TEXCOORD0,
	in float3 iNormal : NORMAL,
#if defined(NORMALMAP_ENABLED) && defined(VERTEX_TANGENTS)
	in float3 iTangent : TANGENT,
#endif

#if defined (VERTEX_LIGHTING)
	out float3 vLightResult : COLOR0,
#if defined(SPECULAR_ENABLED) || defined(SPECULARMAP_ENABLED)
	out float3 vSpecularResult : COLOR1,
#endif
#endif

	out float2 vTexCoord : TEXCOORD0,

#if !defined(VERTEX_LIGHTING)
	out float3 vViewNormal : TEXCOORD1,
#if defined(NORMALMAP_ENABLED) && defined(VERTEX_TANGENTS)
	out float3 vViewTangent : TEXCOORD2,
#endif
	out float3 vViewPosition : TEXCOORD3,
#endif

	out float vDepth : TEXCOORD4,
#if defined(SHADOWRECEIVER) 
	out float4 vLightSpacePos1 : TEXCOORD5,
#if defined(PSSM_ENABLED)
	out float4 vLightSpacePos2 : TEXCOORD6,
	out float4 vLightSpacePos3 : TEXCOORD7,
#endif
#endif

	out float4 oPosition : SV_POSITION
)
{
	oPosition = mul(wvpMat, iPosition);

	vTexCoord = iTexCoord;

#if defined(VERTEX_LIGHTING)
	float3 vViewPosition, vViewNormal;
#endif
	vViewPosition = mul(worldViewMat, float4(iPosition.xyz, 1.0)).xyz;
	vViewNormal = mul(worldViewMat, float4(iNormal.xyz, 0.0)).xyz;
#if !defined(VERTEX_LIGHTING) && defined(NORMALMAP_ENABLED) && defined(VERTEX_TANGENTS)
	vViewTangent = mul(worldViewMat, float4(iTangent.xyz, 0.0)).xyz;
#endif

	vDepth = oPosition.z;

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
	float3 vertexNormal = safe_normalize(vViewNormal);
	float3 pixelToLight = safe_normalize(lightPosition[0].xyz - (vViewPosition * lightPosition[0].w));
	
	// accumulate diffuse lighting
	float attenuation = max(dot(vertexNormal, pixelToLight.xyz), 0.0);
#if defined(OG_RETRO_MODE)
	attenuation = saturate(attenuation * 0.55 + 0.20);
#endif
	vLightResult = lightDiffuse[0].xyz * attenuation;

#if defined(SPECULAR_ENABLED) || defined(SPECULARMAP_ENABLED)
	// per-pixel view reflection
	float3 viewReflect = reflect(safe_normalize(vViewPosition), vertexNormal);

	// accumulate specular lighting
	attenuation *= pow(max(dot(viewReflect, pixelToLight), 0.0), materialShininess);
	vSpecularResult = lightSpecular[0].xyz * attenuation;
#endif
#endif
}

// -------------------------------------------

void base_fragment(
	uniform Texture2D diffuseMap : register(t0),
	uniform SamplerState diffuseSam : register(s0),
#if defined(NORMALMAP_ENABLED) 
	uniform Texture2D normalMap : register(t1),
	uniform SamplerState normalSam : register(s1),
#endif
#if defined(SPECULARMAP_ENABLED)
	uniform Texture2D specularMap : register(t2),
	uniform SamplerState specularSam : register(s2),
#endif
#if defined(EMISSIVEMAP_ENABLED)
	uniform Texture2D emissiveMap : register(t3),
	uniform SamplerState emissiveSam : register(s3),
#endif
#if defined(SHADOWRECEIVER) 
	uniform Texture2D shadowMap1 : register(t4),	
	uniform SamplerState shadowSam1 : register(s4),
#if defined(PSSM_ENABLED)
	uniform Texture2D shadowMap2 : register(t5),
	uniform SamplerState shadowSam2 : register(s5),
	uniform Texture2D shadowMap3 : register(t6),
	uniform SamplerState shadowSam3 : register(s6),
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
	uniform float transparency,

#if defined (VERTEX_LIGHTING)
	in float3 vLightResult : COLOR0,
#if defined(SPECULAR_ENABLED) || defined(SPECULARMAP_ENABLED)
	in float3 vSpecularResult : COLOR1,
#endif
#endif
	in float2 vTexCoord : TEXCOORD0,
#if !defined(VERTEX_LIGHTING)
	in float3 vViewNormal : TEXCOORD1,
#if defined(NORMALMAP_ENABLED) && defined(VERTEX_TANGENTS)
	in float3 vViewTangent : TEXCOORD2,
#endif
	in float3 vViewPosition : TEXCOORD3,
#endif
	in float vDepth : TEXCOORD4,
#if defined(SHADOWRECEIVER) 
	in float4 vLightSpacePos1 : TEXCOORD5,
#if defined(PSSM_ENABLED)
	in float4 vLightSpacePos2 : TEXCOORD6,
	in float4 vLightSpacePos3 : TEXCOORD7,
#endif
#endif

	out float4 oColor : SV_TARGET
#if defined(LOGDEPTH_ENABLE)
	, out float oDepth : SV_DEPTH
#endif
)
{
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
#if defined(OG_RETRO_MODE)
	shadow = shadow * 0.5 + 0.5;
#endif
#endif

#if defined(VERTEX_LIGHTING)

	// combine ambient and shadowed light result
	float3 lightResult = vLightResult;
#if defined(SHADOWRECEIVER)
	lightResult *= shadow;
#endif
#if defined(OG_RETRO_MODE)
	lightResult += max(sceneAmbient.xyz * 1.10, float3(0.22, 0.22, 0.22));
#else
	lightResult += sceneAmbient.xyz;
#endif

#if defined(SPECULAR_ENABLED) || defined(SPECULARMAP_ENABLED)
	float3 specularResult = vSpecularResult;
#endif
	
#else

	// per-pixel view position
	float3 viewPos = vViewPosition;

#if defined(NORMALMAP_ENABLED) 
	// tangent basis
#if defined(VERTEX_TANGENTS)
	float3 baseNormal = safe_normalize(vViewNormal);
	float3 baseTangent = safe_normalize(vViewTangent);
	float3 binormal = safe_normalize(cross(baseTangent, baseNormal));
	float3x3 tbn = float3x3(baseTangent, binormal, baseNormal);
#else
	float3x3 tbn = cotangent_frame(safe_normalize(vViewNormal), vViewPosition.xyz, vTexCoord);
#endif

	// per-pixel view normal
	float3 normalTex = normalMap.Sample(normalSam, vTexCoord).xyz * 2.0 - 1.0;
	float3 viewNormal = safe_normalize(mul(normalTex.xyz, tbn));
#else
	float3 viewNormal = safe_normalize(vViewNormal);
#endif

	// start with ambient light and no specular
#if defined(OG_RETRO_MODE)
	float3 lightResult = max(sceneAmbient.xyz * 1.10, float3(0.22, 0.22, 0.22));
#else
	float3 lightResult = sceneAmbient.xyz;
#endif
#if defined(SPECULAR_ENABLED) || defined(SPECULARMAP_ENABLED)
	float3 specularResult = float3(0,0,0);
#endif

#if defined(SPECULAR_ENABLED) || defined(SPECULARMAP_ENABLED)
	// per-pixel view reflection
	float3 viewReflect = reflect(safe_normalize(viewPos), viewNormal);
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
		float d = max(length(pixelToLight), 1e-6);
		pixelToLight *= rcp(d);

			// compute distance attentuation
			float attenuation = saturate(1.0 / 
				(lightAttenuation[i].y + d * (lightAttenuation[i].z + d * lightAttenuation[i].w)));

			// compute spotlight attenuation
			// it's much faster to just do the math than have a branch on low-end GPUs
			// non-spotlights have falloff power 0 which yields a constant output
			float spotRange = max(spotLightParams[i].x - spotLightParams[i].y, 1e-6);
			attenuation *= pow(clamp(
				(dot(pixelToLight, safe_normalize(-lightDirection[i].xyz)) - spotLightParams[i].y) /
				spotRange, 1e-30, 1.0), spotLightParams[i].z);

#if defined(SHADOWRECEIVER) 
			// apply shadow attenuation
			attenuation *= shadow;
#endif

			// accumulate diffuse lighting
			float diffuseTerm = max(dot(viewNormal, pixelToLight), 0.0);
#if defined(OG_RETRO_MODE)
			diffuseTerm = saturate(diffuseTerm * 0.55 + 0.20);
#endif
			attenuation *= diffuseTerm;
			lightResult.xyz += lightDiffuse[i].xyz * attenuation;

#if defined(SPECULAR_ENABLED) || defined(SPECULARMAP_ENABLED)
			// accumulate specular lighting
			attenuation *= pow(max(dot(viewReflect, pixelToLight), 0.0), materialShininess);
			specularResult.xyz += lightSpecular[i].xyz * attenuation;
#endif

#if defined(SHADOWRECEIVER) 
		// clear shadow attenuation
		shadow = 1.0;
#endif
	}

#endif

	// diffuse texture
	float4 diffuseTex = diffuseMap.Sample(diffuseSam, vTexCoord);
	oColor.xyz = lightResult.xyz * diffuseTex.xyz;

#if defined(SPECULARMAP_ENABLED)
	// specular texture
	float3 specularTex = specularMap.Sample(specularSam, vTexCoord).xyz;
	oColor.xyz += specularResult.xyz * specularTex.xyz;
#elif defined(SPECULAR_ENABLED)
	oColor.xyz += specularResult.xyz;
#endif

#if defined(EMISSIVEMAP_ENABLED)
	// emissive texture
	float3 emissiveTex = emissiveMap.Sample(emissiveSam, vTexCoord).xyz;
	oColor.xyz += emissiveTex.xyz;
#endif

	// fog
	float fogValue = saturate((vDepth - fogParams.y) * fogParams.w);
	oColor.xyz = lerp(oColor.xyz, fogColour.xyz, fogValue);

	// output alpha
	//oColor.a = diffuseTex.a;
	oColor.a = saturate(transparency);

#if defined(LOGDEPTH_ENABLE)	
	// logarithmic depth
	const float C = 0.1;
	const float far = 1e+09;
	const float offset = 1.0;
	oDepth = log(C * vDepth + offset) / log(C * far + offset);
#endif
}
