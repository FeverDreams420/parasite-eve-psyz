#version 450

layout(location = 0) in vec4 vertexColor;
layout(location = 1) in vec2 rawUV;
layout(location = 2) flat in uint tpage;
layout(location = 3) flat in uint clut;
layout(location = 4) flat in uint textureMode;
layout(location = 5) flat in uint subPixelMask;
layout(location = 6) flat in uint texelShift;
layout(location = 7) flat in uint indexShift;
layout(location = 8) flat in uint indexMask;
layout(location = 9) flat in uint dither;
layout(location = 10) flat in ivec2 pageBase;
layout(location = 11) flat in uvec4 texWindow;
layout(location = 12) flat in uint polygon;

layout(set = 2, binding = 0) uniform sampler2D texVram;
layout(set = 2, binding = 1) uniform sampler2D texBlend;
layout(set = 3, binding = 0) uniform PassMode { uvec4 passMode; };

float attributeRoundingBias() {
    // Native 1:1 polygon attributes occupy a 1/4096 lattice. Half an LSB
    // repairs floating interpolation just below an exact integer without
    // rounding the preceding representable value up to it.
    return polygon != 0u && passMode.y == 1u && passMode.z != 0u
        ? 1.0 / 8192.0 : 0.0;
}

uvec2 resolveTexel() {
    // PS1 interpolates at integer pixel coordinates, the GPU at pixel centres.
    vec2 uv = polygon != 0u ? rawUV + attributeRoundingBias() :
        rawUV - 0.5 * (dFdx(rawUV) + dFdy(rawUV)) + 1.0 / 512.0;
    uvec2 texel = uvec2(ivec2(floor(uv))) & uvec2(255u);
    return (texel & texWindow.xy) | texWindow.zw;
}

layout(location = 0) out vec4 FragColor;

uint rgb5551ToU16(vec4 c) {
    uint r = uint(c.r * 31.0 + 0.5);
    uint g = uint(c.g * 31.0 + 0.5);
    uint b = uint(c.b * 31.0 + 0.5);
    uint a = uint(c.a + 0.5);
    return r | (g << 5u) | (b << 10u) | (a << 15u);
}

const mat4 ditherMatrix = mat4(
    -4.0, +0.0, -3.0, +1.0,
    +2.0, -2.0, +3.0, -1.0,
    -3.0, +1.0, -4.0, +0.0,
    +3.0, -1.0, +2.0, -2.0);
vec3 applyDither(vec3 c) {
    if (dither == 0u) return clamp(floor(c * 255.0 / 8.0), 0.0, 31.0) / 31.0;
    int dx = int(gl_FragCoord.x) & 3;
    int dy = int(gl_FragCoord.y) & 3;
    float off = ditherMatrix[dy][dx];
    vec3 c8 = c * 255.0 + off;
    vec3 c5 = clamp(floor(c8 / 8.0), 0.0, 31.0);
    return c5 / 31.0;
}

void main() {
    vec4 texColor;
    if (textureMode == 0u) { // untextured
        texColor = vec4(1, 1, 1, 2);
    } else if (textureMode == 1u) { // 16-bit bitmap
        texColor = texelFetch(texVram, pageBase + ivec2(resolveTexel()), 0);
    } else { // indexed
        ivec2 texel = ivec2(resolveTexel());
        uint subPixel = uint(texel.x) & subPixelMask;
        ivec2 texelPos = ivec2(texel.x >> texelShift, texel.y);
        uint word16 = rgb5551ToU16(texelFetch(texVram, pageBase + texelPos, 0));
        uint colorIdx = (word16 >> (subPixel * indexShift)) & indexMask;
        ivec2 clutBase = ivec2((clut % 64u) * 16u, clut / 64u);
        texColor = texelFetch(texVram, clutBase + ivec2(colorIdx, 0), 0);
    }
    // check for full transparency
    if (texColor == vec4(0, 0, 0, 0)) {
        if (passMode.x != 0u) discard;
        FragColor = vec4(0);
        return;
    }
    if (passMode.x == 1u) {
        FragColor = vec4(0,0,0,textureMode == 0u ? 0.0 : texColor.a);
        return;
    }
    // check for setSemiTrans(p, 1)
    bool isSemiTrans = vertexColor.a < 0.75;
    // when a color has the 0x8000 bit left then it has the semitrans flag on
    bool colorSemiTrans = texColor.a > 0;
    // PS1-accurate texture-color modulation: (tex5 * col8) >> 7, clamp to 31
    vec3 modColor;
    if (textureMode == 0u) {
        // untextured: PS1 uses color directly, no modulation
        modColor = texColor.rgb * (vertexColor.rgb + attributeRoundingBias() / 255.0);
    } else {
        vec3 tex5 = floor(texColor.rgb * 31.0 + 0.5);
        vec3 col8 = min(floor(vertexColor.rgb * 127.5 +
                             (polygon != 0u ? attributeRoundingBias() : 0.5)), vec3(255.0));
        vec3 prod8 = min(tex5 * col8 / 16.0, vec3(255.0));
        modColor = dither != 0u ? prod8 / 255.0
                                : floor(prod8 / 8.0) / 31.0;
    }
    modColor = applyDither(modColor);
    if (passMode.x == 2u) {
        ivec3 color = ivec3(floor(modColor * 31.0 + 0.5));
        if (colorSemiTrans && isSemiTrans) {
            ivec3 back = ivec3(floor(texelFetch(texBlend,
                ivec2(gl_FragCoord.xy), 0).rgb * 31.0 + 0.5));
            uint abr = (tpage & 0x60u) >> 5u;
            if (abr == 0u) color = (back + color) >> 1;
            else if (abr == 1u) color = back + color;
            else if (abr == 2u) color = back - color;
            else color = back + (color >> 2);
        }
        FragColor = vec4(vec3(clamp(color,ivec3(0),ivec3(31))) / 31.0,
                         textureMode == 0u ? 0.0 : texColor.a);
        return;
    }
    // pre-multiplied alpha output for ONE, ONE_MINUS_SRC_ALPHA blending
    if (colorSemiTrans && isSemiTrans) {
        uint abr = (tpage & 0x60u) >> 5u;
        if (abr == 0u) {
            FragColor = vec4(modColor * 0.5, 0.5); // 50% blend
        } else if (abr == 1u) {
            FragColor = vec4(modColor, 0.0); // additive
        } else if (abr == 2u) {
            FragColor = vec4(modColor, 0.0); // subtractive
        } else {                                  // abr == 3u
            FragColor = vec4(modColor * 0.25, 0.0); // B + F/4
        }
    } else {
        FragColor = vec4(modColor, 1.0); // full opacity
    }
}
