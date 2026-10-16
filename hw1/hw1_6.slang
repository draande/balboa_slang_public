/* for each pixel...
    split into an n by n grid
    find center of each cell
    run the same rendering logic as 1.4 for each sample
    add sample colors together
    average them for the final pixel color */

import hw1_common;

[shader("compute")]
[numthreads(8, 8, 1)]
void compute_main(uint2 tid : SV_DispatchThreadID,
                uniform float3 background,
                // new. supersampling. how many samples per axis, at least 1
                uniform int samples_per_axis,
                StructuredBuffer<Shape> shapes,
                uniform int num_shapes,
                StructuredBuffer<Circle> circles,
                StructuredBuffer<Polyline> polylines,
                StructuredBuffer<QuadraticBezier> /*quadratic_beziers*/,
                StructuredBuffer<float2> points,
                RWTexture2D<float4> image) {
    uint width, height;
    image.GetDimensions(width, height);
    if (tid.x >= width || tid.y >= height) {
        return;
    }

    // number of samples per axis, at least 1
    int n = max(samples_per_axis, 1);
    // add colors of all samples
    float3 total = float3(0.0);

    // check n by n grid of samples inside each pixel
    for (int row = 0; row < n; row++) {
        for (int col = 0; col < n; col++) {
            // instead of checking just the pixel center, we split the pixel
            // into an n by n grid and check the center of each little cell.
            // col and row pick the cell, and + 0.5 moves to its center.
            // dividing by n keeps the offsets inside the pixel.
            // i still flip y like in 1.4 so positive y goes upward. 
            float x = float(tid.x) + (col + 0.5) / float(n);
            float y = float(height) - float(tid.y) - (row + 0.5) / float(n);
            float2 pixel = float2(x, y);

            float3 color = background;

            // lotsa 1.3 logic

            // work backward. earlier shapes cover later shapes.
            // i want to draw from the back to the front.
            // because i want the earlier objects can overlap
            // over the later ones. so if i put down the later ones
            // first, then as i work my way through, the can
            // place shapes ON TOP of the things i just drew.
            for (int i = num_shapes - 1; i >= 0; i--) {
                Shape shape = shapes[i];

                // move the pixel into the shape's original coordinate system.
                // this undoes the shape's translation, rotation, and scaling,
                // so i can reuse the same fill and stroke checks from 1.3.
                // the extra 1.0 lets the matrix handle translation too.
                float3 transformed = mul(shape.world_to_obj, float3(pixel, 1.0));
                float2 q = transformed.xy;

                // check if pixel is inside the shape's fill or stroke
                bool fillHit = false;
                bool strokeHit = false;
                float halfWidth = shape.stroke_width * 0.5;

                if (shape.type == ShapeType.Circle) {
                    // which circle to use for this shape
                    Circle circle = circles[shape.index];
                    float distance = length(q - circle.center);

                    // check if pixel is inside the circle's fill or stroke
                    fillHit = distance <= circle.radius;
                    // distance from circle boundary
                    strokeHit = abs(distance - circle.radius) <= halfWidth;
                } 
                
                else if (shape.type == ShapeType.Polyline) {
                    Polyline path = polylines[shape.index];

                    // all paths have pointsBuffer
                    // start at begin and go to end
                    int begin = path.pts_begin;
                    int count = path.pts_end - begin;

                    if (count < 2) { continue; }

                    if (path.closed && shape.use_fill) {
                        int up = 0;
                        int down = 0;
                        int prev = count - 1;

                        // ray crossings algorithm to determine if pixel is inside the polyline
                        // lotsa 1.2 logic
                        for (int j = 0; j < count; j++) {
                            float2 p0 = points[begin + prev];
                            float2 p1 = points[begin + j];
                            prev = j;

                            // both points above q
                            if (p0.y > q.y) {
                                if (p1.y > q.y) {
                                    continue;
                                }
                            }
                            // both points at or below q
                            if (p0.y <= q.y) {
                                if (p1.y <= q.y) {
                                    continue;
                                }
                            }
                            // straight from lectures
                            // intersecting edge with horizontal ray from q
                            float t = (q.y - p0.y) / (p1.y - p0.y);
                            float s = p0.x + t * (p1.x - p0.x) - q.x;
                            
                            // right crossings only
                            if (s <= 0) { continue; }

                            if (p1.y < p0.y) { down++; } 
                            else { up++; }
                        }
                        
                        // if the number of up and down intersections 
                        // are different, the point is inside the polygon
                        fillHit = up != down;
                    }

                    // lotsa 1.2 logic for stroke
                    if (shape.use_stroke) {
                        // open polylines have one less segment than points
                        int segments = count - 1;

                        if (path.closed) { segments = count; }

                        for (int j = 0; j < segments; j++) {
                            int next = j + 1;

                            // wrap around
                            if (next == count) { next = 0; }

                            float2 p0 = points[begin + j];
                            float2 p1 = points[begin + next];
                            // vector from p0 to p1
                            float2 direction = p1 - p0;
                            // vector from p0 to pixel center
                            float2 offset = q - p0;

                            // t = dot(direction, offset) / dot(direction, direction)
                            float numerator = direction.x * offset.x
                                            + direction.y * offset.y;
                            float denominator = direction.x * direction.x
                                              + direction.y * direction.y;
                            
                            if (denominator == 0) { continue; }

                            float t = numerator / denominator;

                            // i dont want to color pixels that are past the ends of the edge
                            if (t < 0 || t > 1) { continue; }

                            // closest point on the edge to the pixel center
                            float2 closest_point = p0 + t * direction;

                            // if the pixel center is within half the
                            // stroke width of the edge, color it
                            if (length(q - closest_point) <= halfWidth) {
                                strokeHit = true;
                                break;
                            }
                        }

                        // round joins
                        for (int j = 0; j < count; j++) {
                            if (strokeHit) { break; }
                            // open endpoints flat
                            if (!path.closed) {
                                if (j == 0 || j == count - 1) { 
                                    continue; 
                                }
                            }
                            // pixel center to joining vertex
                            if (length(q - points[begin + j]) <= halfWidth) {
                                strokeHit = true;
                            }
                        }
                    }
                }

                // fill first, then stroke
                // xyz has rgb, leaving out alpha
                if (shape.use_fill && fillHit) {
                    color = shape.fill_rgba.xyz;
                }
                // stroke override fill
                if (shape.use_stroke && strokeHit) {
                    color = shape.stroke_rgba.xyz;
                }
            }
            // add its color to total
            total += color;
        }
    }

    // n * n samples were checked, divide to get their average color
    image[tid] = float4(total / float(n * n), 1.0);
}