/*A huge chunk of this is code form 1.7. Again, I'm using the same stuff 
for sampling, transformations, circles, polylines, alpha blending, etc.
Pretty much the only new stuff is Bezier fill and stroke.*/

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
                StructuredBuffer<QuadraticBezier> quadratic_beziers,
                StructuredBuffer<float2> points,
                RWTexture2D<float4> image) {
    uint width, height;
    image.GetDimensions(width, height);
    if (tid.x >= width || tid.y >= height) {
        return;
    }

    image[tid] = float4(0.5, 0.5, 0.5, 1.0);
    // TODO: your code here

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
                            // project q - p0 to edge
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
                            // right intersects only
                            if (s <= 0.0) { continue; }

                            if (p1.y > p0.y) { mainCalcs++; }
                            else { mainCalcs--; }
                        }

                        // if not zero, q is inside
                        fillHit = mainCalcs != 0;
                    }
                }

                else if (shape.type == ShapeType.QuadraticBezier) {
                    QuadraticBezier path = quadratic_beziers[shape.index];

                    int begin = path.pts_begin;
                    int count = path.pts_end - begin;

                    if (count < 3) { continue; }

                    // open paths end at last point
                    // closed paths use last control point to return to first
                    int curves = (count - 1) / 2;
                    if (path.closed) { curves = count / 2; }

                    int mainCalcs = 0;

                    // each curve advances two points, sharing its endpoint
                    for (int j = 0; j < curves; j++) {
                        int start = j * 2;
                        int next = start + 2;

                        if (next == count) { next = 0; }

                        float2 p0 = points[begin + start];
                        float2 p1 = points[begin + start + 1];
                        float2 p2 = points[begin + next];

                        // curve(t) = a*t*t + b*t + p0
                        float2 a = p0 - 2.0 * p1 + p2;
                        float2 b = 2.0 * (p1 - p0);

                        if (path.closed && shape.use_fill) {
                            float2 roots = float2(0.0);
                            int numRoots = 0;

                            // solve a.y*t*t + b.y*t + p0.y - q.y = 0
                            if (a.y == 0.0) {
                                if (b.y != 0.0) {
                                    roots.x = (q.y - p0.y) / b.y;
                                    numRoots = 1;
                                }
                            } 
                            
                            else {
                                if (solve_quadratic(a.y, b.y, p0.y - q.y, roots)) {
                                    numRoots = 2;
                                    // repeated root is one intersection
                                    if (roots.x == roots.y) {
                                        numRoots = 1;
                                    }
                                }
                            }

                            for (int k = 0; k < numRoots; k++) {
                                float t = roots[k];
                                // intersects only
                                if (t < 0.0 || t > 1.0) { continue; }

                                float2 hit = (a * t + b) * t + p0;
                                float s = hit.x - q.x;

                                if (s <= 0.0) { continue; }

                                // crossing direction
                                float tangentY = 2.0 * a.y * t + b.y;

                                if (tangentY == 0.0) {
                                    // interior tangent touches without crossing
                                    if (t > 0.0) {
                                        if (t < 1.0) { 
                                            continue; 
                                        } 
                                    }

                                    // handle endpoint with an horizontal tangent
                                    // curve rises above ray 
                                    if (a.y <= 0.0) { continue; }

                                    if (t == 0.0) { mainCalcs++; }
                                    else { mainCalcs--; }

                                    continue;
                                }

                                // count shared endpoints only once
                                // lower endpoints good. upper bad
                                // no double counting
                                if (t == 0.0 && tangentY < 0.0) { continue; }
                                if (t == 1.0 && tangentY > 0.0) { continue; }

                                if (tangentY > 0.0) { mainCalcs++; }
                                else { mainCalcs--; }
                            }
                        }

                        if (shape.use_stroke && !strokeHit && halfWidth > 0.0) {
                            float2 offset = p0 - q;

                            // (curve(t) - q) dot curve'(t) = 0
                            // c3*t*t*t + c2*t*t + c1*t + c0 = 0
                            float c3 = 2.0 * dot(a, a);
                            float c2 = 3.0 * dot(a, b);
                            float c1 = dot(b, b) + 2.0 * dot(a, offset);
                            float c0 = dot(b, offset);

                            float3 roots = float3(0.0);
                            int numRoots = 0;

                            // straight curve reduces the cubic to a line
                            if (c3 == 0.0) {
                                if (c1 != 0.0) {
                                    roots.x = -c0 / c1;
                                    numRoots = 1;
                                }
                            } 
                            else {
                                numRoots = solve_cubic(c3, c2, c1, c0, roots);
                            }

                            for (int k = 0; k < numRoots; k++) {
                                float t = roots[k];

                                if (t <= 0.0 || t >= 1.0) { continue; }

                                float2 closest = (a * t + b) * t + p0;

                                if (length(q - closest) <= halfWidth) {
                                    strokeHit = true;
                                    break;
                                }
                            }

                            // endpoints also need distance checks
                            // internal endpoints form round joins
                            bool first = !path.closed && j == 0;
                            bool last = !path.closed && j == curves - 1;

                            float2 startTangent = p1 - p0;
                            float2 endTangent = p2 - p1;

                            if (length(startTangent) == 0.0) {
                                startTangent = p2 - p0;
                            }
                            if (length(endTangent) == 0.0) {
                                endTangent = p2 - p0;
                            }

                            // clip the open endpoint disks to keep caps flat
                            if (length(q - p0) <= halfWidth) {
                                if (!first || dot(q - p0, startTangent) >= 0.0) {
                                    strokeHit = true;
                                }
                            }

                            if (length(q - p2) <= halfWidth) {
                                if (!last || dot(q - p2, endTangent) <= 0.0) {
                                    strokeHit = true;
                                }
                            }
                        }
                    }

                    fillHit = mainCalcs != 0;
                }

                // stroke is in front of this shape's fill
                if (shape.use_stroke && strokeHit) {
                    float4 rgba = shape.stroke_rgba;
                    color += remaining * rgba.w * rgba.xyz;
                    remaining *= 1.0 - rgba.w;
                }

                // blend fill separately so it can show through stroke
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