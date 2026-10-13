import hw1_common;

[shader("compute")]
[numthreads(8, 8, 1)]
void compute_main(uint2 tid : SV_DispatchThreadID,
                // ID array on GPU. Read only.
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

    // pixel center
    float x = tid.x + 0.5;
    float y = float(height) - float(tid.y) - 0.5;
    float2 q = float2(x,y);

    /*  q + (1,0)s = p0 + t(p1 - p0)
        qy = p0y + t(p1y - p0y) 
        t = (qy - p0y) / (p1y - p0y) */

    // only closed polylines are filled
    if (is_closed)
        if (use_fill_color) {
            int up = 0;
            int down = 0;

            int prev = num_polyline - 1;

            for (int i = 0; i < num_polyline; i++) {
                float2 p0 = polyline[prev];
                float2 p1 = polyline[i];
                prev = i;
                
                // both endpoints are above center
                if (p0.y > q.y) {
                    if (p1.y > q.y) {
                        continue;
                    }
                }

                // both endpoints are at/below center
                if (p0.y <= q.y) {
                    if (p1.y <= q.y) {
                        continue;
                    }
                }
                
                // where intersection happens (vals 0 -> 1)
                float t = (q.y - p0.y) / (p1.y - p0.y);
                
                /*  horizontal dist to intersection 
                    s > 0: right of pixel
                    s < 0: left of pixel
                    s = 0: at pixel */
                float s = p0.x + t * (p1.x - p0.x) - q.x;

                // left intersections not valid
                if (s <= 0) {
                    continue;
                }
                
                // assign tags correctly
                if (p1.y < p0.y) { down++; } 
                else { up++; }
            }
            
            // unequal == nonzero winding
            if (up != down) {
                image[tid] = float4(fill_color, 1.0);
            }
        }

    int polylines = 0;

    // closing a path means last point connects to first
    if (is_closed) { polylines = num_polyline; }
    else { polylines = num_polyline - 1; }

    // t = ((p1 - p0) (q - p0)) / ((p1 - p0)^2)

    if (use_stroke_color) {
        float half_stroke_width = stroke_width * 0.5;

        for (int i = 0; i < polylines; i++) {
            int next = i + 1;

            if (next == num_polyline) {
                next = 0;
            }

            float2 p0 = polyline[i];
            float2 p1 = polyline[next];
            float2 direction = p1 - p0;
            float2 offset = q - p0;

            // dot products
            float numerator = direction.x * offset.x + direction.y * offset.y;
            float denominator = direction.x * direction.x + direction.y * direction.y;
            
            if (denominator == 0) {
                continue;
            }

            float t = numerator / denominator;

            // clamp t to the segment
            if (t < 0.0 || t > 1.0) {
                continue;
            }

            float2 closest_point = p0 + t * direction;

            float distance = length(q - closest_point);

            if (distance <= half_stroke_width) {
                image[tid] = float4(stroke_color, 1.0);
            }
        }

        // add circles at joining vertices for round corners
        // skipping open endpoints to keep their caps flat
        int joins = num_polyline;

        while (joins > 0) {
            joins--;

            bool rounded = is_closed;

            if (joins < num_polyline - 1) {
                if (joins > 0) {
                    rounded = true;
                }
            }

            if (rounded) {
                float dist = length(q - polyline[joins]);

                if (dist <= half_stroke_width) {
                    image[tid] = float4(stroke_color, 1.0);
                }
            }
        }
    }
}