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

    // render multiple shapes in renderer

    // pixel center
    float x = tid.x + 0.5;
    float y = float(height) - float(tid.y) - 0.5;
    float2 q = float2(x, y);

    float3 color = background;

    // I used AI to help build this loop. I wanted 
    // to track how much i'm covering, and then apply 
    // the colors. I had a hard time putting my thoughts
    // together. But the idea of the stroke extending
    // half its width inside and outside the edge wasn't AI.
    for (int i = num_shapes - 1; i >= 0; i--) {
        Shape shape = shapes[i];

        bool fillHit = false;
        bool strokeHit = false;
        float halfWidth = shape.stroke_width * 0.5;

        if (shape.type == ShapeType.Circle) {
            Circle circle = circles[shape.index];
            float distance = length(q - circle.center);

            fillHit = distance <= circle.radius;
            strokeHit = abs(distance - circle.radius) <= halfWidth;
        } 
        
        else if (shape.type == ShapeType.Polyline) {
            Polyline path = polylines[shape.index];

            // using a range for the shared points
            int begin = path.pts_begin;
            int count = path.pts_end - begin;

            if (count < 2) { continue; }

            if (path.closed && shape.use_fill) {
                int up = 0;
                int down = 0;
                // CLOSE THE EDGE FROM THE LAST POINT TO THE FIRST
                // I used AI for this. I could not
                // troubleshoot this by myself
                int prev = count - 1;

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
                    
                    // straight from lectures!
                    // intersecting edge with horizontal ray from q
                    float t = (q.y - p0.y) / (p1.y - p0.y);
                    float s = p0.x + t * (p1.x - p0.x) - q.x;

                    // right crossings only
                    if (s <= 0) { continue; }

                    if (p1.y < p0.y) { down++; } 
                    else { up++; }
                }

                fillHit = up != down;
            }

            if (shape.use_stroke) {
                int segments = count - 1;

                if (path.closed) { segments = count; }

                for (int j = 0; j < segments; j++) {
                    int next = j + 1;

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

                    if (t < 0 || t > 1) { continue; }

                    float2 closest_point = p0 + t * direction;
                    float distance = length(q - closest_point);

                    if (distance <= halfWidth) {
                        strokeHit = true;
                        break;
                    }
                }

                // round joins
                for (int j = 0; j < count; j++) {
                    if (strokeHit) { break; }

                    // leave open endpoints flat
                    if (!path.closed) {
                        if (j == 0 || j == count - 1) {
                            continue;
                        }
                    }

                    float distance = length(q - points[begin + j]);

                    if (distance <= halfWidth) {
                        strokeHit = true;
                    }
                }
            }
        }

        // fill first, then stroke
        if (shape.use_fill && fillHit) {
            color = shape.fill_rgba.xyz;
        }

        if (shape.use_stroke && strokeHit) {
            color = shape.stroke_rgba.xyz;
        }
    }

    image[tid] = float4(color, 1.0);
}