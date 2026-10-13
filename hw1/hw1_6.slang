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

    int n = max(samples_per_axis, 1);
    float3 total = float3(0.0);

    for (int row = 0; row < n; row++) {
        for (int col = 0; col < n; col++) {
            // center of each subpixel
            float x = float(tid.x) + (col + 0.5) / float(n);
            float y = float(height) - float(tid.y) - (row + 0.5) / float(n);
            float2 pixel = float2(x, y);

            float3 color = background;

            // i want to draw from the back to the front.
            // because i want the earlier objects can overlap
            // over the later ones. so if i put down the later ones
            // first, then as i work my way through, the can
            // place shapes ON TOP of the things i just drew.
            for (int i = num_shapes - 1; i >= 0; i--) {
                Shape shape = shapes[i];

                // move sample into shape space
                float3 transformed = mul(shape.world_to_obj, float3(pixel, 1.0));
                float2 q = transformed.xy;

                bool fillHit = false;
                bool strokeHit = false;
                float halfWidth = shape.stroke_width * 0.5;

                if (shape.type == ShapeType.Circle) {
                    Circle circle = circles[shape.index];
                    float distance = length(q - circle.center);

                    fillHit = distance <= circle.radius;

                    // the stroke has to be centerd on the edge
                    strokeHit = abs(distance - circle.radius) <= halfWidth;
                } 
                
                else if (shape.type == ShapeType.Polyline) {
                    Polyline path = polylines[shape.index];

                    // i want each path to use its own 
                    // range in the shared points bugger
                    int begin = path.pts_begin;
                    int count = path.pts_end - begin;

                    if (count < 2) {
                        continue;
                    }

                    if (path.closed && shape.use_fill) {
                        int up = 0;
                        int down = 0;
                        int prev = count - 1;

                        for (int j = 0; j < count; j++) {
                            float2 p0 = points[begin + prev];
                            float2 p1 = points[begin + j];
                            prev = j;

                            // only edges crossing q's height
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

                            float t = (q.y - p0.y) / (p1.y - p0.y);
                            float s = p0.x + t * (p1.x - p0.x) - q.x;

                            if (s <= 0) { continue; }

                            if (p1.y < p0.y) { down++; } 
                            else { up++; }
                        }
                        
                        // if the number of up and down intersections 
                        // are different, the point is inside the polygon
                        fillHit = up != down;
                    }

                    if (shape.use_stroke) {
                        int segments = count - 1;

                        if (path.closed) { segments = count; }

                        for (int j = 0; j < segments; j++) {
                            int next = j + 1;

                            // wrap around for the closing segment
                            if (next == count) { next = 0; }

                            float2 p0 = points[begin + j];
                            float2 p1 = points[begin + next];
                            float2 direction = p1 - p0;
                            float2 offset = q - p0;

                            // t = dot(direction, offset) / dot(direction, direction)
                            float numerator = direction.x * offset.x
                                            + direction.y * offset.y;
                            float denominator = direction.x * direction.x
                                              + direction.y * direction.y;
                            // skip repeated points to avoid divisionByZero
                            if (denominator == 0) { continue; }

                            float t = numerator / denominator;

                            // flat segment ends
                            if (t < 0 || t > 1) { continue; }

                            float2 closest_point = p0 + t * direction;

                            if (length(q - closest_point) <= halfWidth) {
                                strokeHit = true;
                                break;
                            }
                        }

                        // round joins, but leave open endpoints flat
                        for (int j = 0; j < count; j++) {
                            if (strokeHit) { break; }
                            // open endpoints flat
                            if (!path.closed) {
                                if (j == 0 || j == count - 1) { 
                                    continue; 
                                }
                            }

                            if (length(q - points[begin + j]) <= halfWidth) {
                                strokeHit = true;
                            }
                        }
                    }
                }
                // the stroke needs to cover the the whole shape's fill
                if (shape.use_fill && fillHit) {
                    color = shape.fill_rgba.xyz;
                }

                if (shape.use_stroke && strokeHit) {
                    color = shape.stroke_rgba.xyz;
                }
            }

            total += color;
        }
    }

    // normalize accumulated color
    image[tid] = float4(total / float(n * n), 1.0);
}