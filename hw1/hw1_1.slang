/* general purpose GPU progs 
   performing general computation.
   launches many threads in parallel */
[shader("compute")]
/* 2D groups of 8*8=64 threads.*/
[numthreads(8, 8, 1)]

/* entry point. tid is 2D unsigned int vector to rep
    current thread's position in the 2D grid.*/
void compute_main(uint2 tid : SV_DispatchThreadID,
                // sam values across threads  
                uniform float2 center,
                uniform float radius,
                uniform float3 color,
                // output. each pixel has a float4 (RGBA)
                RWTexture2D<float4> image) {
    uint width, height;
    image.GetDimensions(width, height);
    /* make sure dimensions have multiples
    pf 8 (as per threads) */
    if (tid.x >= width || tid.y >= height) {
        return;
    }

    // gray bg
    image[tid] = float4(0.5, 0.5, 0.5, 1.0);
    
    // TODO: your code here

    // centers
    float x = tid.x + 0.5;
    float y = float(height) - float(tid.y) - 0.5;

    // how far pixel is from center
    // pythagorean theorem
    float xDistance = x - center.x;
    float yDistance = y - center.y;
    float hypotenuse = sqrt(xDistance * xDistance + yDistance * yDistance);

    // if pixel inside circle, set color
    if (hypotenuse <= radius) {
        image[tid] = float4(color, 1.0);
    }
}