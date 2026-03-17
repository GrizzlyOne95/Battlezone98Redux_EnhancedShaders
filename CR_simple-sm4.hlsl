void simple_vertex(
	uniform float4x4 wvpMat,
	uniform float4x4 worldViewMat,

	in float4 iPosition : POSITION,
	in float3 iNormal : NORMAL,
	in float2 iTexCoord : TEXCOORD0,
	in float4 iDiffuse : COLOR0,

	out float2 vTexCoord : TEXCOORD0,
	out float3 vViewPosition : TEXCOORD1,
	out float3 vViewNormal : TEXCOORD2,
	out float vDepth : TEXCOORD3,
	out float4 vColor : COLOR,

	out float4 oPosition : SV_POSITION
)
{
	oPosition = mul(wvpMat, iPosition);
	vTexCoord = iTexCoord;
	vViewPosition = mul(worldViewMat, float4(iPosition.xyz, 1.0)).xyz;
	vViewNormal = mul(worldViewMat, float4(iNormal.xyz, 0.0)).xyz;
	vDepth = oPosition.z;
	
	vColor = iDiffuse.bgra;
}

// -------------------------------------------


#define MAX_LIGHTS 1

void simple_fragment(
	uniform Texture2D diffuseMap : register(t0),
	uniform SamplerState diffuseSam : register(s0),

	uniform float4 sceneAmbient,
	uniform float materialShininess,

	uniform float4 lightDiffuse[MAX_LIGHTS],
	uniform float4 lightPosition[MAX_LIGHTS],
	uniform float4 lightSpecular[MAX_LIGHTS],
	uniform float4 lightAttenuation[MAX_LIGHTS],
	uniform float4 spotLightParams[MAX_LIGHTS],
	uniform float4 lightDirection[MAX_LIGHTS],

	in float2 vTexCoord : TEXCOORD0,
	in float3 vViewPosition : TEXCOORD1,
	in float3 vViewNormal : TEXCOORD2,
	in float vDepth : TEXCOORD3,
	in float4 vColor : COLOR,

	out float4 oColor : SV_TARGET
#ifdef LOGDEPTH_ENABLE	
	, out float oDepth : SV_DEPTH
#endif
)
{
	// per-pixel view position
	float3 viewPos = vViewPosition;

	// per-pixel view normal
	float3 viewNormal = vViewNormal;

	// per-pixel direction to the eyepoint
	float3 eyeDir = normalize(-viewPos.xyz);

	// start with ambient light and no specular
	float3 lightResult = sceneAmbient.xyz;
	float4 specularResult = float4(0,0,0,1);

	// per-pixel view reflection
	float3 viewReflect = reflect(-eyeDir, viewNormal);

	// for each possible light source...
#if MAX_LIGHTS > 1
	for (int i=0; i<MAX_LIGHTS; ++i)
#else
	const int i = 0;
#endif
	{
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
				(dot(pixelToLight, normalize(-lightDirection[i].xyz)) - spotLightParams[i].y) /
				(spotLightParams[i].x - spotLightParams[i].y), 1e-30, 1.0), spotLightParams[i].z);

			// accumulate diffuse lighting
			attenuation *= max(dot(viewNormal, pixelToLight), 0.0);
			lightResult.xyz += lightDiffuse[i].xyz * attenuation;

			// accumulate specular lighting
			attenuation *= pow(max(dot(viewReflect, pixelToLight), 0.0), materialShininess);
			specularResult.xyz += lightSpecular[i].xyz * attenuation;
	}

	// diffuse texture
	float4 diffuseTex = diffuseMap.Sample(diffuseSam, vTexCoord);
	oColor.xyz = lightResult.xyz * vColor.xyz * diffuseTex.xyz;
	
	// specular
	oColor.xyz += specularResult.xyz;

	// output alpha
	oColor.a = vColor.a;

#ifdef LOGDEPTH_ENABLE	
	// logarithmic depth
	const float C = 0.1;
	const float far = 1e+09;
	const float offset = 1.0;
	oDepth = log(C * vDepth + offset) / log(C * far + offset);
#endif
}

void simple_zero_vertex(
	uniform float4x4 wvpMat,

	in float4 iPosition : POSITION,

	out float vDepth : TEXCOORD0,

	out float4 oPosition : SV_POSITION
)
{
	oPosition = mul(wvpMat, iPosition);
	vDepth = oPosition.z;
}

void simple_zero_fragment(
	in float vDepth : TEXCOORD0,

	out float4 oColor : SV_TARGET
#ifdef LOGDEPTH_ENABLE	
	, out float oDepth : SV_DEPTH
#endif
)
{
	oColor = float4(0,0,0,0);
	
#ifdef LOGDEPTH_ENABLE
	// logarithmic depth
	const float C = 0.1;
	const float far = 1e+09;
	const float offset = 1.0;
	oDepth = log(C * vDepth + offset) / log(C * far + offset);
#endif
}

void single_tex_vertex(
	uniform float4x4 wvpMat,

	in float4 iPosition : POSITION,
	in float2 iTexCoord : TEXCOORD0,

	out float vDepth : TEXCOORD1,
	out float2 vTexCoord : TEXCOORD0,

	out float4 oPosition : SV_POSITION
)
{
	oPosition = mul(wvpMat, iPosition);
	vDepth = oPosition.z;
	vTexCoord = iTexCoord;
}

void single_tex_fragment(
	uniform Texture2D diffuseMap : register(t0),
	uniform SamplerState diffuseSam : register(s0),

	in float vDepth : TEXCOORD1,
	in float2 vTexCoord : TEXCOORD0,

	out float4 oColor : SV_TARGET
#ifdef LOGDEPTH_ENABLE	
	, out float oDepth : SV_DEPTH
#endif
)
{
	oColor = diffuseMap.Sample(diffuseSam, vTexCoord);
	
#ifdef LOGDEPTH_ENABLE
	// logarithmic depth
	const float C = 0.1;
	const float far = 1e+09;
	const float offset = 1.0;
	oDepth = log(C * vDepth + offset) / log(C * far + offset);
#endif
}
