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

    // n by n grid for each pixel
    for (int row = 0; row < n; row++) {
        for (int col = 0; col < n; col++) {
            // center
            float x = float(tid.x) + (col + 0.5) / float(n);
            float y = float(height) - float(tid.y)
                    - (row + 0.5) / float(n);
            float2 pixel = float2(x, y);

            float3 color = float3(0.0);
            float remaining = 1.0;

            // front to back
            for (int i = 0; i < num_shapes; i++) {
                Shape shape = shapes[i];

                // test sample point
                float3 transformed = mul(shape.world_to_obj,
                                        float3(pixel, 1.0));
                float2 q = transformed.xy;

                bool fillHit = false;
                bool strokeHit = false;
                float halfWidth = shape.stroke_width * 0.5;

                if (shape.type == ShapeType.Circle) {
                    Circle circle = circles[shape.index];
                    float distance = length(q - circle.center);

                    fillHit = distance <= circle.radius;

                    // i want the stroke to be centered on the edge
                    strokeHit = abs(distance - circle.radius) <= halfWidth;
                } 
                
                else if (shape.type == ShapeType.Polyline) {
                    Polyline path = polylines[shape.index];

                    // range for shared points 
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
                            float2 edge = p1 - p0;
                            float edgeLength = length(edge);

                            // AVOID DivisionByZero
                            // used AI for this check; did not think of it for some reason!
                            if (edgeLength == 0.0) { continue; }

                            // dot product
                            float x = q.x - p0.x;
                            float y = q.y - p0.y;
                            float l = ((edge.x * x) + (edge.y * y)) / edgeLength;

                            // if its past the flat segment, REJECT
                            if (l < 0.0 || l > edgeLength) {
                                continue;
                            }

                            float2 closest = p0 + l * edge / edgeLength;

                            if (length(q - closest) <= halfWidth) {
                                strokeHit = true;
                                break;
                            }
                        }

                        // round joins, flat open caps
                        for (int j = 0; j < count; j++) {
                            if (strokeHit) { break; }

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

                    // fill can show through a transparent stroke
                    if (path.closed && shape.use_fill) {
                        int mainCalcs = 0;
                        int prev = count - 1;

                        for (int j = 0; j < count; j++) {
                            float2 p0 = points[begin + prev];
                            float2 p1 = points[begin + j];
                            prev = j;

                            // count shared vertices only once
                            if ((p0.y > q.y) == (p1.y > q.y)) { continue; }

                            // calculate intersection point
                            float t = (q.y - p0.y) / (p1.y - p0.y);
                            float s = p0.x + t * (p1.x - p0.x) - q.x;

                            if (s <= 0.0) { continue; }

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
                    color += remaining * rgba.w * rgba.xyz;
                    remaining *= 1.0 - rgba.w;
                }

                if (shape.use_fill && fillHit) {
                    float4 rgba = shape.fill_rgba;
                    color += remaining * rgba.w * rgba.xyz;
                    remaining *= 1.0 - rgba.w;
                }

                if (remaining == 0.0) {
                    break;
                }
            }

            color += remaining * background;
            total += color;
        }
    }

    image[tid] = float4(total / float(n * n), 1.0);
}