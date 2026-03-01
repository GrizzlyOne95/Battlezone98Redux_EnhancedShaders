static const float gaussSamples[13] =
{
   0.002216,
   0.008764,
   0.026995,
   0.064759,
   0.120985,
   0.176033,
   0.199471,
   0.176033,
   0.120985,
   0.064759,
   0.026995,
   0.008764,
   0.002216
};

float4 downsample(
		uniform Texture2D  rt : register(t0),
		uniform SamplerState s : register(s0),

		float2 uv: TEXCOORD0
	) : SV_TARGET
{
	float4 colOut = rt.Sample(s, uv);
	const float3 lumaW = float3(0.299, 0.587, 0.114);
	const float glowThreshold = 0.62;
	const float glowKnee = 0.28;
	float luma = dot(colOut.rgb, lumaW);
	float glowMask = saturate((luma - glowThreshold) / glowKnee);
	glowMask = glowMask * glowMask * (3.0 - 2.0 * glowMask);
	colOut.rgb *= colOut.rgb;
	colOut.rgb *= glowMask;
	return colOut;
}

float4 blurH(
		uniform Texture2D  rt : register(t0),
		uniform SamplerState s : register(s0),

		uniform float4 invMapSize,
		uniform float scaleGlowOffset,

		float2 uv: TEXCOORD0
	) : SV_TARGET
{
   float4 colOut = float4(0, 0, 0, 0);
   for (int i = 0; i < 13; i++)
   {
      colOut += rt.Sample(s, uv + float2(-0.5 + float(i - 6) * scaleGlowOffset, -0.5) * invMapSize.xy) * gaussSamples[i];
   }
   return colOut;
}

float4 blurV(
		uniform Texture2D  rt : register(t0),
		uniform SamplerState s : register(s0),

		uniform float4 invMapSize,
		uniform float scaleGlowOffset,

		float2 uv: TEXCOORD0
	) : SV_TARGET
{
   float4 colOut = float4(0, 0, 0, 0);
   for (int i = 0; i < 13; i++)
   {
      colOut += rt.Sample(s, uv + float2(0.5, 0.5 + float(i - 6) * scaleGlowOffset) * invMapSize.xy) * gaussSamples[i];
   }
   return colOut;
}

float4 main_ps(
		uniform Texture2D sceneMap: register(t0),
		uniform SamplerState sceneSam: register(s0),

		uniform Texture2D blurMap: register(t1),
		uniform SamplerState blurSam: register(s1),

		uniform float glowPower,

		float2 uv: TEXCOORD0
	) : SV_TARGET
{
	float4 sceneTex = sceneMap.Sample(sceneSam, uv);
	float3 blurTex = blurMap.Sample(blurSam, uv).rgb;
	blurTex = blurTex / (1.0 + blurTex * 0.8);
	return float4(sceneTex.rgb + blurTex * glowPower, sceneTex.a);
}
