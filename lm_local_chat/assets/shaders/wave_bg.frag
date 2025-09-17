#version 320 es
precision mediump float;

uniform float uTime;
uniform vec2 uResolution;
uniform vec3 uColorA;
uniform vec3 uColorB;

out vec4 fragColor;

void main() {
  vec2 uv = gl_FragCoord.xy / uResolution.xy;
  float wave = sin((uv.y + uTime * 0.05) * 12.0) * 0.02;
  float gradient = smoothstep(0.0, 1.0, uv.y + wave);
  float glow = smoothstep(0.4, 0.6, gradient);
  vec3 color = mix(uColorA, uColorB, glow);
  fragColor = vec4(color, 1.0);
}
