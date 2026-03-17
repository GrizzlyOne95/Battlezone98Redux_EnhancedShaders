#version 120

uniform sampler2D diffuseMap;

varying vec4 vColor;
varying vec2 vTexCoord;

void main()
{
    vec4 diffuseTex = texture2D(diffuseMap, vTexCoord);
    gl_FragData[0] = diffuseTex * vColor;
}
