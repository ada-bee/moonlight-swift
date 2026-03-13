#include <metal_stdlib>

using namespace metal;

struct MetalVideoVertexOut {
    float4 position [[position]];
    float2 textureCoordinate;
};

vertex MetalVideoVertexOut metalVideoVertex(
    const device float4 *vertices [[buffer(0)]],
    uint vertexID [[vertex_id]]
) {
    MetalVideoVertexOut out;
    const float4 vertexData = vertices[vertexID];
    out.position = float4(vertexData.xy, 0.0, 1.0);
    out.textureCoordinate = float2(vertexData.z, vertexData.w);
    return out;
}

fragment float4 metalVideoFragment(
    MetalVideoVertexOut in [[stage_in]],
    texture2d<float, access::sample> lumaTexture [[texture(0)]],
    texture2d<float, access::sample> chromaTexture [[texture(1)]]
) {
    constexpr sampler videoSampler(mag_filter::linear, min_filter::linear, address::clamp_to_edge);

    const float ySample = lumaTexture.sample(videoSampler, in.textureCoordinate).r;
    const float2 uvSample = chromaTexture.sample(videoSampler, in.textureCoordinate).rg;

    const float y = ySample;
    const float cb = uvSample.x - 0.5;
    const float cr = uvSample.y - 0.5;

    float3 rgb;
    rgb.r = y + 1.5748 * cr;
    rgb.g = y - 0.187324 * cb - 0.468124 * cr;
    rgb.b = y + 1.8556 * cb;

    return float4(saturate(rgb), 1.0);
}
