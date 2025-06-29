//
//  Shaders.metal
//  Wavefunction Screensaver
//
//  Created by acemavrick on 6/28/25.
//

#include <metal_stdlib>
using namespace metal;

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

// a fragment shader that creates a color gradient based on pixel coordinates
fragment float4 fragmentShader(VertexOut in [[stage_in]],
                                  constant float2& viewportSize [[buffer(0)]])
{
    float2 uv = in.position.xy / viewportSize;
    return float4(uv.x, uv.y, 0.5, 1.0);
} 