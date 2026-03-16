// Stock DX9 base vertex path with minimal GPU skinning support layered in.

#if defined(SKINNED)
#ifndef SKINNED_MAX_BONES
#define SKINNED_MAX_BONES 72
#endif
uniform float3x4 worldMatrix3x4Array[SKINNED_MAX_BONES];
#endif

void base_vertex(
	uniform float4x4 wvpMat,
	uniform float4x4 worldViewMat,
#if defined(SKINNED)
	uniform float4x4 inverseWorldMat,
#endif

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
#if !defined(VERTEX_LIGHTING) && defined(NORMALMAP_ENABLED) && defined(VERTEX_TANGENTS)
	in float3 iTangent : TANGENT,
#endif
#if defined(SKINNED)
	in float4 iBlendIndices : BLENDINDICES,
	in float4 iBlendWeights : BLENDWEIGHT,
#endif

#if defined(VERTEX_LIGHTING)
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

	out float4 oPosition : POSITION
)
{
#if defined(SKINNED)
	float3x4 blendMatrix =
		iBlendWeights.x * worldMatrix3x4Array[(int)(iBlendIndices.x + 0.5)] +
		iBlendWeights.y * worldMatrix3x4Array[(int)(iBlendIndices.y + 0.5)] +
		iBlendWeights.z * worldMatrix3x4Array[(int)(iBlendIndices.z + 0.5)] +
		iBlendWeights.w * worldMatrix3x4Array[(int)(iBlendIndices.w + 0.5)];

	float4 worldBlendPos = float4(mul(blendMatrix, float4(iPosition.xyz, 1.0)).xyz, 1.0);
	float3 worldBlendNorm = mul((float3x3)blendMatrix, iNormal).xyz;
	float4 blendPos = mul(inverseWorldMat, worldBlendPos);
	float3 blendNorm = mul((float3x3)inverseWorldMat, worldBlendNorm).xyz;
#if !defined(VERTEX_LIGHTING) && defined(NORMALMAP_ENABLED) && defined(VERTEX_TANGENTS)
	float3 worldBlendTang = mul((float3x3)blendMatrix, iTangent).xyz;
	float3 blendTang = mul((float3x3)inverseWorldMat, worldBlendTang).xyz;
#endif
#else
	float4 blendPos = iPosition;
	float3 blendNorm = iNormal;
#if !defined(VERTEX_LIGHTING) && defined(NORMALMAP_ENABLED) && defined(VERTEX_TANGENTS)
	float3 blendTang = iTangent;
#endif
#endif

	oPosition = mul(wvpMat, blendPos);
	vTexCoord = iTexCoord;

#if defined(VERTEX_LIGHTING)
	float3 vViewPosition, vViewNormal;
#endif
	vViewPosition = mul(worldViewMat, float4(blendPos.xyz, 1.0)).xyz;
	vViewNormal = mul(worldViewMat, float4(blendNorm.xyz, 0.0)).xyz;
#if !defined(VERTEX_LIGHTING) && defined(NORMALMAP_ENABLED) && defined(VERTEX_TANGENTS)
	vViewTangent = mul(worldViewMat, float4(blendTang.xyz, 0.0)).xyz;
#endif

	vDepth = oPosition.z;

#if defined(SHADOWRECEIVER)
	vLightSpacePos1 = mul(texWorldViewProj1, blendPos);
#if defined(PSSM_ENABLED)
	vLightSpacePos2 = mul(texWorldViewProj2, blendPos);
	vLightSpacePos3 = mul(texWorldViewProj3, blendPos);
#endif
#endif

#if defined(VERTEX_LIGHTING)
	float3 pixelToLight = normalize(lightPosition[0].xyz - (vViewPosition * lightPosition[0].w));

	float attenuation = max(dot(vViewNormal, pixelToLight.xyz), 0.0);
	vLightResult = lightDiffuse[0].xyz * attenuation;

#if defined(SPECULAR_ENABLED) || defined(SPECULARMAP_ENABLED)
	float3 viewReflect = reflect(normalize(vViewPosition), vViewNormal);
	attenuation *= pow(max(dot(viewReflect, pixelToLight), 0.0), materialShininess);
	vSpecularResult = lightSpecular[0].xyz * attenuation;
#endif
#endif
}
