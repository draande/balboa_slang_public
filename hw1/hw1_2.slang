import hw1_common;

[shader("compute")]
[numthreads(8, 8, 1)]
void compute_main(uint2 tid : SV_DispatchThreadID,
                // ID array on GPU. R only.
                StructuredBuffer<float2> polyline,
                uniform int num_polyline,
                uniform bool is_closed,
                uniform bool use_fill_color,
                uniform float3 fill_color,
                uniform bool use_stroke_color,
                uniform float3 stroke_color,
                uniform float stroke_width,
                RWTexture2D<float4> image) {
    uint width, height;
    image.GetDimensions(width, height);
    if (tid.x >= width || tid.y >= height) {
        return;
    }

    // gray bg
    image[tid] = float4(0.5, 0.5, 0.5, 1.0);
    
    // TODO: your code here

}