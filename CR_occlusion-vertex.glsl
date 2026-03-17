#version 120

uniform mat4 wvpMat;

attribute vec4 vertex;
attribute vec4 colour;

varying vec4 vColor;

void main()
 {
    gl_Position = wvpMat * vertex;
    vColor = colour.bgra;
}
