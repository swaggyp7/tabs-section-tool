-- Intersect a voxel row with a convex volume. Each constraint is:
-- lo <= a*x + b*y + c*z + d <= hi, evaluated at voxel centers.
-- No engine calls: shared by the game and the geometry tests.
SectionClip = {}
function SectionClip.box(planes, x, y, z)
    local full = true
    for _, p in ipairs(planes) do
        local lo, hi = p.d, p.d
        for k, coefficient in ipairs({p.a,p.b,p.c}) do
            local size = ({x,y,z})[k]
            local a,b = coefficient*0.5, coefficient*(size-0.5)
            lo,hi = lo+math.min(a,b), hi+math.max(a,b)
        end
        if hi < p.lo-1e-8 or lo > p.hi+1e-8 then return "outside" end
        if lo < p.lo-1e-8 or hi > p.hi+1e-8 then full=false end
    end
    return full and "full" or "partial"
end
function SectionClip.row(planes, y, z, sizeX)
    local first, last = 0, sizeX - 1
    for i = 1, #planes do
        local p = planes[i]
        local v = p.b * (y + 0.5) + p.c * (z + 0.5) + p.d + p.a * 0.5
        if math.abs(p.a) < 1e-10 then
            if v < p.lo - 1e-8 or v > p.hi + 1e-8 then return nil end
        else
            local a, b = (p.lo - v) / p.a, (p.hi - v) / p.a
            if a > b then a, b = b, a end
            first = math.max(first, math.ceil(a - 1e-8))
            last = math.min(last, math.floor(b + 1e-8))
            if first > last then return nil end
        end
    end
    return first, last
end
