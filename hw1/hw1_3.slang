// render multiple shapes in renderer

import hw1_common;

[shader("compute")]
[numthreads(8, 8, 1)]
void compute_main(uint2 tid : SV_DispatchThreadID,
                  uniform float3 background,
                  uniform int /*samples_per_axis*/, // ignore for now
                  StructuredBuffer<Shape> shapes,
                  uniform int num_shapes,
                  StructuredBuffer<Circle> circles,
                  StructuredBuffer<Polyline> polylines,
                  StructuredBuffer<QuadraticBezier> /*quadratic_beziers*/, // ignore for now
                  StructuredBuffer<float2> points,
                  RWTexture2D<float4> image) {
    uint width, height;
    image.GetDimensions(width, height);
    if (tid.x >= width || tid.y >= height) {
        return;
    }

    // used AI to comment out this line
    // image[tid] = float4(0.5, 0.5, 0.5, 1.0);

    // TODO: your code here

    // used AI for this line
    image[tid] = float4(background, 1.0);
    
    // pixel center
    float x = tid.x + 0.5;
    float y = float(height) - float(tid.y) - 0.5;
    float2 q = float2(x,y);


}
