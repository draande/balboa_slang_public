/* for each pixel... 
    start with gray bg, 
    find center,
    shoot ray to right 
    count upward crosses
    count downward crosses
    
    for each stroke...
    check how far pixel is from edge
    color if within half stroke width
    reject points past the ends 
    
    circles at joining vertices for rounding */

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

    // gray pixel 
    image[tid] = float4(0.5, 0.5, 0.5, 1.0);
    
    // TODO: your code here

    // pixel center
    float x = tid.x + 0.5;
    float y = float(height) - float(tid.y) - 0.5;
    float2 q = float2(x,y);

    /*  q + (1,0)s = p0 + t(p1 - p0)
        qy = p0y + t(p1y - p0y) 
        t = (qy - p0y) / (p1y - p0y) */

    /*  q: the pixel’s center.
        (1, 0): the ray’s direction, straight right.
        s: horizontal distance from the pixel to the intersection. Positive means right.
        p0, p1: the edge’s starting and ending points.
        t: how far along the edge the intersection is. 0 is the start, 1 is the end.
        qy, p0y, p1y: the y-coordinates of those points.*/

    // only closed polylines are filled
    if (is_closed)
        if (use_fill_color) {
            int up = 0;
            int down = 0;
            // last point in  polyline, so we can connect it to first point
            int prev = num_polyline - 1;

            // parse thru, each edge is line segment from p0 to p1
            for (int i = 0; i < num_polyline; i++) {
                float2 p0 = polyline[prev];
                float2 p1 = polyline[i];
                prev = i;
                
                // these edges can't cross the ray, skip

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
                // t = 0: intersection at p0
                // t = 1: intersection at p1
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
            
            // unequal == nonzero "turns"
            if (up != down) {
                image[tid] = float4(fill_color, 1.0);
            }
        }

    // count how many edges i need to stroke

    int numEdges = 0;
    
    /* idea for 4-vertex stroke
        open path: 3 edges
        closed path: 4 edges (last->first) */ 

    // closing a path means last point connects to first
    if (is_closed) { numEdges = num_polyline; }
    else { numEdges = num_polyline - 1; }

    // t = ((p1 - p0) (q - p0)) / ((p1 - p0)^2)
    
    // each stroke has half its size on either side of the edge

    if (use_stroke_color) {
        float half_stroke_width = stroke_width * 0.5;

        // get "next" vertex at sny given edge, wrap back around if closed
        for (int i = 0; i < numEdges; i++) {
            int next = i + 1;

            if (next == num_polyline) {
                next = 0;
            }

            float2 p0 = polyline[i];
            float2 p1 = polyline[next];
            // vector from p0 to p1
            float2 direction = p1 - p0;
            // vector from p0 to pixel center
            float2 offset = q - p0;

            // dot products. make the equation
            float numerator = direction.x * offset.x + direction.y * offset.y;
            float denominator = direction.x * direction.x + direction.y * direction.y;
            
            if (denominator == 0) {
                continue;
            }

            float t = numerator / denominator;

            // i dont want to color pixels that are past the ends of the edge
            if (t < 0.0 || t > 1.0) {
                continue;
            }

            // closest point on the edge to the pixel center
            float2 closest_point = p0 + t * direction;
            float distance = length(q - closest_point);

            // if the pixel center is within half the 
            // stroke width of the edge, color it
            if (distance <= half_stroke_width) {
                image[tid] = float4(stroke_color, 1.0);
            }
        }

        // add circles at joining vertices for round corners
        // skipping open endpoints to keep their caps flat

        int joins = num_polyline;

        // backwards so i can skip the last vertex if open
        while (joins > 0) {
            joins--;

            // every vertex gets circled
            bool rounded = is_closed;

            // skip first and last vertex if open
            // only internal vertices get rounded 
            if (joins < num_polyline - 1) {
                if (joins > 0) {
                    rounded = true;
                }
            }

            // if pixel in joining vertex circle, color it
            if (rounded) {
                float dist = length(q - polyline[joins]);

                if (dist <= half_stroke_width) {
                    image[tid] = float4(stroke_color, 1.0);
                }
            }
        }
    }
}