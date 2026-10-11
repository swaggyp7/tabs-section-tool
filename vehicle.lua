-- TABS uses jointed vehicle parts plus independently animated, unphysical tracks.
SectionVehicle = {}
local function valid(h) return h and h ~= 0 and IsHandleValid(h) end
local function resolveAttached(shape)
    if not valid(shape) then return 0 end
    local body = GetShapeBody(shape)
    local vehicle = GetBodyVehicle(body)
    if valid(vehicle) then return vehicle end
    vehicle = GetEntityParent(body, "", "vehicle")
    if valid(vehicle) then return vehicle end
    if IsBodyDynamic(body) then
        for _, linked in ipairs(GetJointedBodies(body)) do
            vehicle = GetBodyVehicle(linked)
            if valid(vehicle) then return vehicle end
        end
    end
    return 0
end

local function center(body)
    local lo, hi = GetBodyBounds(body)
    return VecScale(VecAdd(lo, hi), 0.5)
end

local function visualTrack(shape)
    -- Do not treat ordinary map geometry as a detached track.
    local x,y,z,s = GetShapeSize(shape)
    if math.max(x,y,z)*s > 3 then return false end
    local entries = GetShapePalette(shape)
    local found, mixedPalette = false, false
    for _, entry in ipairs(entries) do
        if entry ~= 0 then
            local material = GetShapeMaterial(shape, entry)
            if material ~= "" then
                if material ~= "unphysical" then mixedPalette = true end
                found = true
            end
        end
    end
    if found and not mixedPalette then return true end
    -- Imported palettes may contain unused physical materials. Inspect actual
    -- occupied voxels as a bounded fallback; TABS track assets are unphysical.
    local inspected = 0
    for iz=0,z-1 do for iy=0,y-1 do for ix=0,x-1 do
        local material = GetShapeMaterialAtIndex(shape,ix,iy,iz)
        if material ~= "" then return material == "unphysical" end
        inspected = inspected+1
        if inspected >= 4096 then return false end
    end end end
    return false
end

function SectionVehicle.resolve(shape)
    local vehicle = resolveAttached(shape)
    if vehicle ~= 0 then return HasTag(vehicle,"TABS") and vehicle or 0 end
    if not valid(shape) or HasTag(shape,"section_proxy") then return 0 end
    if not visualTrack(shape) then return 0 end
    -- Recognize a directly aimed independent TABS track using the same ownership
    -- heuristic as collection, even before the first section operation.
    local p = center(GetShapeBody(shape))
    local best, distance = 0, math.huge
    for _, v in ipairs(FindVehicles("TABS", true)) do
        local hull = GetVehicleBody(v)
        local lo, hi = GetBodyBounds(hull)
        local inside = true
        for k=1,3 do if p[k]<lo[k]-1.5 or p[k]>hi[k]+1.5 then inside=false end end
        local d = VecLength(VecSub(p,center(hull)))
        if inside and d < distance then best,distance=v,d end
    end
    return best
end

function SectionVehicle.collect(shape)
    local vehicle = SectionVehicle.resolve(shape)
    if vehicle == 0 then return nil, 0 end
    local result, seen = {}, {}
    local function add(s)
        if valid(s) and not seen[s] and not HasTag(s,"section_proxy") then
            seen[s] = true; result[#result+1] = s
        end
    end
    for _, s in ipairs(GetEntityChildren(vehicle, "", true, "shape")) do add(s) end
    local hull = GetVehicleBody(vehicle)
    local bodies = IsBodyDynamic(hull) and GetJointedBodies(hull) or {hull}
    for _, b in ipairs(bodies) do
        local owner = GetBodyVehicle(b)
        if owner == 0 or owner == vehicle then
            for _, s in ipairs(GetBodyShapes(b)) do add(s) end
        end
    end
    add(shape)
    if HasTag(vehicle, "TABS") then
        local lo, hi = GetBodyBounds(hull)
        -- Suspension and track thickness can protrude beyond the hull bounds.
        lo, hi = VecSub(lo, Vec(1.5,1.5,1.5)), VecAdd(hi, Vec(1.5,1.5,1.5))
        local ownCenter, others = center(hull), {}
        for _, v in ipairs(FindVehicles("TABS", true)) do
            if v ~= vehicle then others[#others+1] = center(GetVehicleBody(v)) end
        end
        QueryRequire("") -- Include unphysical and static animated track segments.
        for _, s in ipairs(QueryAabbShapes(lo, hi)) do
            local b = GetShapeBody(s)
            if not seen[s] and not HasTag(s,"section_proxy") and GetBodyVehicle(b) == 0
                and visualTrack(s) then
                local p = center(b)
                local inside = true
                for k=1,3 do if p[k]<lo[k] or p[k]>hi[k] then inside=false end end
                local distance = VecLength(VecSub(p, ownCenter))
                for _, other in ipairs(others) do
                    if VecLength(VecSub(p, other)) <= distance then inside = false end
                end
                if inside then add(s) end
            end
        end
    end
    return result, vehicle
end
