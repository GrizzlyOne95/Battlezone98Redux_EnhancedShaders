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
		uniform sampler2D  rt : register(s0),

		uniform float4 invMapSize,

		float2 uv: TEXCOORD0
	) : COLOR
{
	float4 colOut = tex2D(rt, uv + invMapSize.xy);
	colOut.rgb *= colOut.rgb;
	return colOut;
}

float4 blurH(
		uniform sampler2D  rt : register(s0),

		uniform float4 invMapSize,
		uniform float scaleGlowOffset,

		float2 uv: TEXCOORD0
	) : COLOR
{
   float4 colOut = float4(0, 0, 0, 0);
   for (int i = 0; i < 13; i++)
   {
      colOut += tex2D(rt, uv + float2(float(i - 6) * scaleGlowOffset, 0.5) * invMapSize.xy) * gaussSamples[i];
   }
   return colOut;
}

float4 blurV(
		uniform sampler2D  rt : register(s0),

		uniform float4 invMapSize,
		uniform float scaleGlowOffset,

		float2 uv: TEXCOORD0
	) : COLOR
{
   float4 colOut = float4(0, 0, 0, 0);
   for (int i = 0; i < 13; i++)
   {
      colOut += tex2D(rt, uv + float2(0.5, float(i - 6) * scaleGlowOffset) * invMapSize.xy) * gaussSamples[i];
   }
   return colOut;
}

float4 main_ps(
		uniform sampler2D scene: register(s0),
		uniform sampler2D blurX: register(s1),

		uniform float glowPower,

		float2 uv: TEXCOORD0
	) : COLOR
{
	return tex2D(scene, uv) + tex2D(blurX, uv) * glowPower;
}
