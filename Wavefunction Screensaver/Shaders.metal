//
//  Shaders.metal
//  Wavefunction Screensaver
//
//  Created by acemavrick on 6/28/25.
//

#include <metal_stdlib>
using namespace metal;

struct Uniforms {
    float time;
    float2 resolution;
};

// a struct to pass data from the vertex to the fragment shader
struct VertexOut {
    float4 position [[position]];
};

// a simple vertex shader to draw a full-screen quad
vertex VertexOut vertexShader(uint vertexID [[vertex_id]]) {
    VertexOut out;

    float4 positions[4] = {
        float4(-1.0, -1.0, 0.0, 1.0),
        float4( 1.0, -1.0, 0.0, 1.0),
        float4(-1.0,  1.0, 0.0, 1.0),
        float4( 1.0,  1.0, 0.0, 1.0)
    };
    
    out.position = positions[vertexID];
    return out;
}

kernel void computeKernel(device float2* screenBuffer [[buffer(0)]],
                          constant Uniforms& uniforms [[buffer(1)]],
                          uint2 gid [[thread_position_in_grid]])
{
    uint width = uint(uniforms.resolution.x);
    uint height = uint(uniforms.resolution.y);
    if (gid.x >= width || gid.y >= height) {
        return;
    }

    uint index = gid.y * width + gid.x;
    float2 uv = float2(gid) / uniforms.resolution;

    float x = 0.5 + 0.5 * sin(uv.x * 10.0 + uniforms.time);
    float y = 0.5 + 0.5 * cos(uv.y * 10.0 + uniforms.time);

    screenBuffer[index] = float2(x, y);
}

// a fragment shader that creates a color gradient based on pixel coordinates
fragment float4 fragmentShader(VertexOut in [[stage_in]],
                                constant Uniforms& uniforms [[buffer(0)]],
                                device const float2* screenBuffer [[buffer(1)]])
{
    uint2 loc = uint2(in.position.xy);
    uint width = uint(uniforms.resolution.x);

    uint index = loc.y * width + loc.x;
    float2 value = screenBuffer[index];

    return float4(value.x, value.y, 1.0, 1.0);
} 