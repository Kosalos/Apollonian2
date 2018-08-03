#pragma once
#include <simd/simd.h>

typedef struct {
    float ambient;
    float diffuse;
    float specular;
    float harshness;
    float saturation;
    float gamma;
    float shadowMin;
    float shadowMax;
    float shadowMult;
    float shadowAmt;
} Lighting;

typedef struct {
    vector_float3 camera;
    vector_float3 focus;
    vector_float3 light;
    vector_float3 color;
    int xSize,ySize;
    float minDist;
    float zoom;
    float parallax;
    float multiplier;
    float dali;
    
    Lighting lighting;
    
    float foam;
    float foam2;
    float fog;
    float bend;
    float future[7];
} Control;
