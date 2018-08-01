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
    int xSize,ySize;
    float minDist;
    float zoom;
    float parallax;
    float multiplier;
    float dali;

    float cameraX,cameraY,cameraZ; // swift access
    float focusX,focusY,focusZ;
    float lightX,lightY,lightZ;
    
    Lighting lighting;
} Control;
