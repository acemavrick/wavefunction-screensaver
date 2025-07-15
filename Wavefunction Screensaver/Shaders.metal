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
float get(device float* buffer, int x, int y, float2 dims) {
    if (x < 0 || y < 0 || x >= dims.x || y >= dims.y) {
        return 0.0;
    }
    return buffer[int(x + y * dims.x)];
}

kernel void waveCompute(device float* u_p [[buffer(0)]],
                        device float* u_c [[buffer(1)]],
                        device float* u_n [[buffer(2)]],
                        constant WaveUniforms &uniforms [[buffer(3)]],
                        uint2 gid [[thread_position_in_grid]]) {
    
    uint index = gid.y * uint(uniforms.resolution.x) + gid.x;
    if (index >= uint(uniforms.resolution.x * uniforms.resolution.y)) return;
    
    float laplacianMultiplier = uniforms.dx > 0.0 ? pow(uniforms.dt * uniforms.c / uniforms.dx, 2.0) : 0.0;
    float laplacian = laplacianMultiplier * (get(u_c, gid.x - 1, gid.y, uniforms.resolution) +
                                            get(u_c, gid.x + 1, gid.y, uniforms.resolution) +
                                            get(u_c, gid.x, gid.y - 1, uniforms.resolution) +
                                            get(u_c, gid.x, gid.y + 1, uniforms.resolution) - 4.0 * u_c[index]);
    
    float val = laplacian + 2.0 * u_c[index] - u_p[index];
    val *= uniforms.damper;
    u_n[index] = val;
}

kernel void waveCopy(device float* u_p [[buffer(0)]],
                     device float* u_c [[buffer(1)]],
                     device float* u_n [[buffer(2)]],
                     constant WaveUniforms &uniforms [[buffer(3)]],
                     uint2 gid [[thread_position_in_grid]]) {

    uint index = gid.y * uint(uniforms.resolution.x) + gid.x;
    if (index >= uint(uniforms.resolution.x * uniforms.resolution.y)) return;
    
    u_p[index] = u_c[index];
    u_c[index] = u_n[index];
}

kernel void addDisturbance(device float* u_c [[buffer(0)]],
                           constant DisturbanceUniforms &disturbance [[buffer(1)]],
                           constant WaveUniforms &uniforms [[buffer(2)]],
                           uint2 gid [[thread_position_in_grid]]) {
    
    uint index = gid.y * uint(uniforms.resolution.x) + gid.x;
    if (index >= uint(uniforms.resolution.x * uniforms.resolution.y)) return;
    
    float dist = distance(float2(gid), disturbance.position);
    if (dist < disturbance.radius) {
        float pulse = disturbance.strength * (0.5 * (cos(dist / disturbance.radius * M_PI_F) + 1.0));
        u_c[index] += pulse;
    }
}

// map wave height to color
float3 getColorForHeight(float height) {
    float absHeight = abs(height);
    
    // black for very small amplitudes
    if (absHeight < 0.025) {
        return float3(0.0);
    }
    
    // power function to make wave crests brighter and more prominent
    float intensity = pow(absHeight, 0.75);

    float3 color;
    if (height > 0.0) {
        // positive waves: smooth gradient from deep blue to cyan to pure white
        float3 deep_blue = float3(0.0, 0.2, 0.9);
        float3 cyan = float3(0.1, 0.9, 1.0);
        color = mix(deep_blue, cyan, smoothstep(0.0, 0.5, intensity));
        color = mix(color, float3(1.0), smoothstep(0.5, 1.0, intensity));
    } else {
        // negative waves: smooth gradient from deep magenta to hot pink to pure white
        float3 deep_magenta = float3(0.8, 0.0, 0.6);
        float3 hot_pink = float3(1.0, 0.3, 0.7);
        color = mix(deep_magenta, hot_pink, smoothstep(0.0, 0.5, intensity));
        color = mix(color, float3(1.0), smoothstep(0.5, 1.0, intensity));
    }
    
    return color * intensity;
}

// filmic tone mapping operator to create a cinematic look
float3 filmicToneMap(float3 color) {
    color = max(float3(0.0), color - 0.004);
    color = (color * (6.2 * color + 0.5)) / (color * (6.2 * color + 1.7) + 0.06);
    return color;
}

fragment float4 waveFragment(VertexOut in [[stage_in]],
                             constant WaveUniforms &uniforms [[buffer(0)]],
                             device const float* u_c [[buffer(1)]])
{
    uint2 loc = uint2(in.position.xy);
    uint width = uint(uniforms.resolution.x);
    uint height = uint(uniforms.resolution.y);
    
    if (loc.x >= width || loc.y >= height) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }
    
    uint index = loc.y * width + loc.x;
    float waveHeight = u_c[index];

    // get base color of the current pixel
    float3 baseColor = getColorForHeight(waveHeight);

    // additive bloom/glow effect
    // sample in a cross pattern (+)
    float3 bloom = float3(0.0);
    const int bloomRadius = 4;
    const float bloomFalloff = 10.0; // falloff
    
    // horizontal samples
    for (int i = -bloomRadius; i <= bloomRadius; ++i) {
        if (i == 0) continue;
        int2 sampleLoc = int2(loc) + int2(i, 0);
        if (sampleLoc.x >= 0 && sampleLoc.x < width) {
            uint sampleIndex = sampleLoc.y * width + sampleLoc.x;
            float sampleHeight = u_c[sampleIndex];
            float weight = exp(-pow(float(i) / float(bloomRadius), 2.0) * bloomFalloff);
            bloom += getColorForHeight(sampleHeight) * weight;
        }
    }
    
    // Vertical samples
    for (int j = -bloomRadius; j <= bloomRadius; ++j) {
        if (j == 0) continue;
        int2 sampleLoc = int2(loc) + int2(0, j);
        if (sampleLoc.y >= 0 && sampleLoc.y < height) {
            uint sampleIndex = sampleLoc.y * width + sampleLoc.x;
            float sampleHeight = u_c[sampleIndex];
            float weight = exp(-pow(float(j) / float(bloomRadius), 2.0) * bloomFalloff);
            bloom += getColorForHeight(sampleHeight) * weight;
        }
    }
    
    // normalize bloom by an approximate weight
    bloom /= (float(bloomRadius) * 1.5);

    // combine and finalize color
    float3 finalColor = baseColor + bloom;
    
    // apply filmic tone mapping for a more pleasing, cinematic result
    finalColor = filmicToneMap(finalColor);
    
    return float4(finalColor, 1.0);
}