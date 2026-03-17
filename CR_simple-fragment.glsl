#version 120

uniform sampler2D diffuseMap;

uniform vec4 sceneAmbient;
uniform float materialShininess;
uniform vec4 lightDiffuse[1];
uniform vec4 lightPosition[1];
uniform vec4 lightSpecular[1];
uniform vec4 lightAttenuation[1];
uniform vec4 spotLightParams[1];
uniform vec4 lightDirection[1];

varying vec2 vTexCoord;
varying vec3 vPos;
varying vec3 vNormal;
varying float vDepth;
varying vec4 vColor;

void main()
{
	vec4 oColor;

	// these need to be multiplied by world view matrix...
	vec3 viewPos = vPos;
	vec3 viewNormal = vNormal;

	// per-pixel direction to the eyepoint
	vec3 eyeDir = normalize(-viewPos.xyz);

	// start with ambient light and no specular
	vec3 lightResult = sceneAmbient.xyz;
	vec4 specularResult = vec4(0.0, 0.0, 0.0, 1.0);

	// per-pixel view reflection
	float3 viewReflect = reflect(-eyeDir, viewNormal);
	
	// for each possible light source...
	for (int i = 0; i < MAX_LIGHTS; ++i)
	{
		// get the direction from the pixel to the light source
		vec3 pixelToLight = lightPosition[i].xyz - (viewPos * lightPosition[i].w);
		float d = length(pixelToLight);
		pixelToLight /= d;
		
			// compute distance attentuation
			float attenuation = clamp(1.0 / 
				(lightAttenuation[i].y + (d * (lightAttenuation[i].z + (d * lightAttenuation[i].w)))),
				0.0, 1.0);
				
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
	vec4 diffuseTex = texture2D(diffuseMap, vTexCoord);
	oColor.xyz = lightResult.xyz * vColor.xyz * diffuseTex.xyz;
  
	// specular
	oColor.xyz += specularResult.xyz;
	
	// output alpha
	oColor.w = vColor.w;

	gl_FragData[0] = vec4(oColor);

#ifdef LOGDEPTH_ENABLE	
	const float C = 0.1;
	const float far = 1e+09;
	const float offset = 1.0;
	gl_FragDepth = log(C * vDepth + offset) / log(C * far + offset);
#endif
}
