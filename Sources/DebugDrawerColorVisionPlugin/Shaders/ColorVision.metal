// The Color Vision plugin's shader, for SwiftUI's `colorEffect`. It ships precompiled: after an
// edit, `just metallibs` compiles it for every platform the module builds for and writes the
// Swift files beside it (ColorVisionShader+<platform>Library.swift), so neither SwiftPM nor Bazel
// needs Xcode's Metal toolchain to build the package.

#include <metal_stdlib>
using namespace metal;

// sRGB's transfer functions (IEC 61966-2-1), odd-extended so extended-range values below zero
// keep their sign.
static float3 linearFromSRGB(float3 encoded) {
    float3 magnitude = abs(encoded);
    float3 linear = select(pow((magnitude + 0.055) / 1.055, 2.4), magnitude / 12.92, magnitude <= 0.04045);
    return sign(encoded) * linear;
}

static float3 sRGBFromLinear(float3 linear) {
    float3 magnitude = abs(linear);
    float3 encoded = select(1.055 * pow(magnitude, 1.0 / 2.4) - 0.055, magnitude * 12.92, magnitude <= 0.0031308);
    return sign(linear) * encoded;
}

// SwiftUI hands the shader each pixel premultiplied and sRGB-encoded. The color is un-premultiplied,
// decoded to linear RGB, multiplied by the 3x3 matrix (nine floats, row by row), clamped to the
// sRGB gamut a dichromat's simulated color lies in, encoded and premultiplied again.
[[ stitchable ]] half4 colorVisionSimulation(float2 position, half4 color, device const float *matrix, int count) {
    if (color.a <= 0.0h || count < 9) {
        return color;
    }
    float alpha = float(color.a);
    float3 linear = linearFromSRGB(float3(color.rgb) / alpha);
    float3x3 transform = float3x3(
        float3(matrix[0], matrix[3], matrix[6]),
        float3(matrix[1], matrix[4], matrix[7]),
        float3(matrix[2], matrix[5], matrix[8])
    );
    float3 simulated = sRGBFromLinear(saturate(transform * linear));
    return half4(half3(simulated * alpha), color.a);
}
