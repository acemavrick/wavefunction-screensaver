//
//  Shaders.metal
//  Wavefunction Screensaver
//
//  Created by acemavrick on 6/28/25.
//

#include <metal_stdlib>
using namespace metal;

struct WaveUniforms {
    float dx;
    float dt;
    float c;
    float time;
    float damper;
    float padding0; // for alignment
    float2 resolution;
    // for colormap, not used in grey fragment shader
    float4 c0, c1, c2, c3, c4, c5, c6;
};

struct DisturbanceUniforms {
    float2 position;
    float radius;
    float strength;
};

// a struct to pass data from the vertex to the fragment shader
struct VertexOut {
    float4 position [[position]];
};

// vertex shader to draw a full-screen quad
vertex VertexOut waveVertex(uint vertexID [[vertex_id]]) {
    float4 positions[4] = {
        float4(-1.0, -1.0, 0.0, 1.0),
        float4( 1.0, -1.0, 0.0, 1.0),
        float4(-1.0,  1.0, 0.0, 1.0),
        float4( 1.0,  1.0, 0.0, 1.0)
    };
    
    VertexOut out;
    out.position = positions[vertexID];
    return out;
}

// function to get a value from the Buffer, with boundary conditions
float get(device float2* buffer, int x, int y, float2 dims) {
    if (x < 0 || y < 0 || x >= dims.x || y >= dims.y) {
        return 0.0;
    }
    // .x is wave height, .y is whether the cell is active (1.0) or blocked (0.0)
    return buffer[int(x + y * dims.x)].x * step(1.0, buffer[int(x + y * dims.x)].y);
}

kernel void waveCompute(device float2* u_p [[buffer(0)]],
                        device float2* u_c [[buffer(1)]],
                        device float2* u_n [[buffer(2)]],
                        constant WaveUniforms &uniforms [[buffer(3)]],
                        uint2 gid [[thread_position_in_grid]]) {
    
    uint index = gid.y * uint(uniforms.resolution.x) + gid.x;
    if (index >= uint(uniforms.resolution.x * uniforms.resolution.y)) return;
    
    // if y is 0, it is a blocked cell, so do nothing
    if (u_c[index].y < 1.0) {
        u_n[index] = float2(0.0, 0.0);
        return;
    }
    
    float laplacianMultiplier = uniforms.dx > 0.0 ? pow(uniforms.dt * uniforms.c / uniforms.dx, 2.0) : 0.0;
    float laplacian = laplacianMultiplier * (get(u_c, gid.x - 1, gid.y, uniforms.resolution) +
                                            get(u_c, gid.x + 1, gid.y, uniforms.resolution) +
                                            get(u_c, gid.x, gid.y - 1, uniforms.resolution) +
                                            get(u_c, gid.x, gid.y + 1, uniforms.resolution) - 4.0 * u_c[index].x);
    
    float val = laplacian + 2.0 * u_c[index].x - u_p[index].x;
    val *= uniforms.damper;
    u_n[index].x = val;
    u_n[index].y = 1.0; // keep it active
}

kernel void waveCopy(device float2* u_p [[buffer(0)]],
                     device float2* u_c [[buffer(1)]],
                     device float2* u_n [[buffer(2)]],
                     constant WaveUniforms &uniforms [[buffer(3)]],
                     uint2 gid [[thread_position_in_grid]]) {

    uint index = gid.y * uint(uniforms.resolution.x) + gid.x;
    if (index >= uint(uniforms.resolution.x * uniforms.resolution.y)) return;
    
    u_p[index] = u_c[index];
    u_c[index] = u_n[index];
}

kernel void addDisturbance(device float2* u_c [[buffer(0)]],
                           constant DisturbanceUniforms &disturbance [[buffer(1)]],
                           constant WaveUniforms &uniforms [[buffer(2)]],
                           uint2 gid [[thread_position_in_grid]]) {
    
    uint index = gid.y * uint(uniforms.resolution.x) + gid.x;
    if (index >= uint(uniforms.resolution.x * uniforms.resolution.y)) return;
    
    float dist = distance(float2(gid), disturbance.position);
    if (dist < disturbance.radius) {
        float pulse = disturbance.strength * (0.5 * (cos(dist / disturbance.radius * M_PI_F) + 1.0));
        u_c[index].x += pulse;
    }
}

fragment float4 waveFragment(VertexOut in [[stage_in]],
                             constant WaveUniforms &uniforms [[buffer(0)]],
                             device const float2* u_c [[buffer(1)]])
{
    uint2 loc = uint2(in.position.xy);
    uint width = uint(uniforms.resolution.x);
    uint height = uint(uniforms.resolution.y);

    if (loc.x >= width || loc.y >= height) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }

    uint index = loc.y * width + loc.x;
    float2 value = u_c[index];

    // render grayscale based on wave height, and black for blocked cells
    return float4(float3(value.x + 0.5), 1.0) * step(1.0, value.y);
} 