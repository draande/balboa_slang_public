/* adds transparency...
    use alpha to decide how much each layer contributes
    blend front to back, stroke before fill
    track how much can still show through
    let layers behind contribute through transparent parts
    stop when nothing behind can contribute
    add background with whatever remains */

import hw1_common;

[shader("compute")]
[numthreads(8, 8, 1)]
void compute_main(uint2 tid : SV_DispatchThreadID,
                uniform float3 background,
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
    // at least one sample per axis
    int n = max(samples_per_axis, 1);
    // sum of all sample colors in this pixel
    float3 total = float3(0.0);

    // n by n grid for each pixel
    for (int row = 0; row < n; row++) {
        for (int col = 0; col < n; col++) {
            // instead of checking just the pixel center, we split the pixel
            // into an n by n grid and check the center of each little cell.
            // col and row pick the cell, and + 0.5 moves to its center.
            // dividing by n keeps the offsets inside the pixel.
            // i still flip y like in 1.4 so positive y goes upward. 
            float x = float(tid.x) + (col + 0.5) / float(n);
            float y = float(height) - float(tid.y)
                    - (row + 0.5) / float(n);
            float2 pixel = float2(x, y);
            
            // no iteratred color
            float3 color = float3(0.0);
            // how much layers behind can still contribute
            // starts at 1 because nothing has blocked them yet
            float remaining = 1.0;

            // work front to back. earlier shapes cover later shapes.
            // add each layer's color based on its alpha and how much
            // is still visible through the layers in front.
            for (int i = 0; i < num_shapes; i++) {
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

                    if (shape.use_stroke) {
                        int segments = count - 1;

                        if (path.closed) { segments = count; }

                        for (int j = 0; j < segments; j++) {
                            int next = j + 1;

                            if (next == count) { next = 0; }

                            float2 p0 = points[begin + j];
                            float2 p1 = points[begin + next];
                            // vector from p0 to p1 and its length
                            float2 edge = p1 - p0;
                            float edgeLength = length(edge);

                            // AVOID DivisionByZero
                            // used AI for this check; did not think of it for some reason!
                            if (edgeLength == 0.0) { continue; }

                            // dot product
                            // x and y are the offset from p0 to q
                            // l is the projected distance along the edge
                            // measured in object-space units, not a 0 to 1 fraction                            
                            float x = q.x - p0.x;
                            float y = q.y - p0.y;
                            float l = ((edge.x * x) + (edge.y * y)) / edgeLength;

                            // if its past the flat segment, REJECT
                            if (l < 0.0 || l > edgeLength) {
                                continue;
                            }
                            
                            // edge / edgeLength gives the unit direction
                            // move l units from p0 to find the closest point
                            float2 closest = p0 + l * edge / edgeLength;

                            if (length(q - closest) <= halfWidth) {
                                strokeHit = true;
                                break;
                            }
                        }

                        // round joins
                        // circles at joining vertices fill the corner gaps
                        for (int j = 0; j < count; j++) {
                            if (strokeHit) { break; }

                            // open endpoints flat
                            if (!path.closed) {
                                if (j == 0 || j == count - 1) {
                                    continue;
                                }
                            }

                            // inside the circle around this joining vertex
                            if (length(q - points[begin + j]) <= halfWidth) {
                                strokeHit = true;
                            }
                        }
                    }

                    // fill can show through a transparent stroke
                    if (path.closed && shape.use_fill) {
                        // crossingCount algorithm
                        int mainCalcs = 0;
                        int prev = count - 1;

                        for (int j = 0; j < count; j++) {
                            float2 p0 = points[begin + prev];
                            float2 p1 = points[begin + j];
                            prev = j;

                            // count shared vertices only once
                            // skip if both endpoints are on the same side
                            // of q's height, also skips horizontal edges
                            if ((p0.y > q.y) == (p1.y > q.y)) { continue; }

                            // calculate intersection point
                            // t- how far along the edge it happens
                            float t = (q.y - p0.y) / (p1.y - p0.y);
                            // s- horizontal distance from q to intersection
                            float s = p0.x + t * (p1.x - p0.x) - q.x;

                            if (s <= 0.0) { continue; }

                            // upward adds one, downward subtracts one
                            if (p1.y > p0.y) { mainCalcs++;} 
                            else { mainCalcs--; }
                        }

                        // if not zero, q is inside
                        fillHit = mainCalcs != 0;
                    }
                }

                // stroke is in front of this shape's fill
                if (shape.use_stroke && strokeHit) {
                    float4 rgba = shape.stroke_rgba;
                    // rgb has the color, w has the alpha
                    color += remaining * rgba.w * rgba.xyz;
                    // remaining is how much layers behind can still contribute
                    remaining *= 1.0 - rgba.w;
                }

                // fill contributes through whatever the stroke left visible
                if (shape.use_fill && fillHit) {
                    float4 rgba = shape.fill_rgba;
                    color += remaining * rgba.w * rgba.xyz;
                    remaining *= 1.0 - rgba.w;
                }
                // note: if the shape is fully opaque, remaining will be 0.0 
                // and nothing behind it can contribute.
                if (remaining == 0.0) {
                    break;
                }
            }
            
            // bg fills whatever is left after all the shapes have been drawn
            color += remaining * background;
            // add this sample's color to the total for this pixel
            total += color;
        }
    }
    // n * n samples were checked, divide to get their average color
    image[tid] = float4(total / float(n * n), 1.0);
}