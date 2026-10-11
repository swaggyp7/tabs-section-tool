#include "clip.lua"
#include "vehicle.lua"

-- Legacy single-player callbacks are intentional (same as built-in jetpack).
local TOOL = "reversible_section_tool"
local MAX_VOXELS, ROWS_PER_TICK = 8000000, 1500
local records, queue, active = {}, {}, nil
local GUIDE_LENGTH = 8
local angle, side = 0, 1
local aim, message, messageTime = nil, "", 0
local batchDone, batchSkipped = 0, 0
local targetShape, targetVehicle, targetRefresh = 0, 0, 0

local function tell(text)
    message, messageTime = text, 5
end

local function equipped()
    return GetString("game.player.tool") == TOOL and GetPlayerVehicle() == 0
end

local function valid(handle)
    return handle and handle ~= 0 and IsHandleValid(handle)
end

local function restore(shape)
    local r = records[shape]
    if not r then return end
    if valid(shape) then
        RemoveTag(shape, "invisible")
        if not r.hadNoShadow then RemoveTag(shape, "noshadow") end
        RemoveTag(shape, "section_original")
    end
    -- Destruction can copy tags to newly created fragments. Restore those too.
    for _, fragment in ipairs(FindShapes("section_original", true)) do
        if GetTagValue(fragment, "section_original") == tostring(shape) then
            RemoveTag(fragment, "invisible")
            if not r.hadNoShadow then RemoveTag(fragment, "noshadow") end
            RemoveTag(fragment, "section_original")
        end
    end
    if valid(r.body) then Delete(r.body) end
    records[shape] = nil
end

local function cancelJob()
    if active and valid(active.body) then Delete(active.body) end
    active, queue = nil, {}
end

local function restoreAll()
    cancelJob()
    local list = {}
    for shape in pairs(records) do list[#list + 1] = shape end
    for _, shape in ipairs(list) do restore(shape) end
    tell("All sections restored")
end

local function rejectHelpers()
    for _, r in pairs(records) do
        if valid(r.body) then QueryRejectBody(r.body) end
    end
    if active and valid(active.body) then QueryRejectBody(active.body) end
    local toolBody = GetToolBody()
    if valid(toolBody) then QueryRejectBody(toolBody) end
end

local function getAim()
    local camera = GetCameraTransform()
    local forward = TransformToParentVec(camera, Vec(0, 0, -1))
    rejectHelpers()
    local hit, distance, _, shape = QueryRaycast(camera.pos, forward, 100, 0, false)
    if hit and (shape ~= targetShape or targetRefresh <= 0) then
        local record = records[shape]
        targetVehicle = record and record.vehicle or SectionVehicle.resolve(shape)
        targetShape, targetRefresh = shape, 0.25
    elseif not hit then targetShape, targetVehicle = 0, 0 end
    local radians = math.rad(angle)
    return {
        hit = hit, shape = shape, vehicle = targetVehicle,
        origin = VecAdd(camera.pos, VecScale(forward, hit and distance or 8)),
        tangent = TransformToParentVec(camera, Vec(math.sin(radians), math.cos(radians), 0)),
        normal = TransformToParentVec(camera, Vec(math.cos(radians), -math.sin(radians), 0)),
        forward = forward, side = side
    }
end

local function point(a, n, t, f)
    return VecAdd(a.origin, VecAdd(VecScale(a.normal, n),
        VecAdd(VecScale(a.tangent, t), VecScale(a.forward, f))))
end

local function planesFor(shape, a, scale)
    local tr = GetShapeWorldTransform(shape)
    local offset = VecSub(tr.pos, a.origin)
    local v = TransformToLocalVec(tr, a.normal)
    return {{a = v[1]*scale, b = v[2]*scale, c = v[3]*scale,
        d = VecDot(offset, a.normal), lo = a.side == 1 and 0 or -1e9,
        hi = a.side == 1 and 1e9 or 0}}
end

local function enqueue(a)
    if active or #queue > 0 then tell("Processing... R cancels and restores"); return end
    if not a.hit then tell("Aim at a TABS vehicle"); return end
    local candidates, vehicle = SectionVehicle.collect(a.shape)
    a.vehicle = vehicle or 0
    if not candidates then tell("TABS vehicles only"); return end
    table.sort(candidates, function(x, y)
        local xp, yp = GetShapeWorldTransform(x).pos, GetShapeWorldTransform(y).pos
        return VecLength(VecSub(xp, a.origin)) < VecLength(VecSub(yp, a.origin))
    end)
    batchDone, batchSkipped = 0, 0
    for _, shape in ipairs(candidates) do
        if valid(shape) and not HasTag(shape, "section_proxy") then
            -- An already-sectioned shape can receive another cut; existing originals stay untouched.
            if not HasTag(shape, "invisible") or records[shape] then
                local x, y, z, scale = GetShapeSize(shape)
                local planes = planesFor(shape, a, scale)
                local coverage = SectionClip.box(planes, x, y, z)
                local alreadyHidden = records[shape] and records[shape].fullyHidden
                if coverage == "outside" or alreadyHidden then
                    -- No work and no loss of the vehicle's queue budget.
                elseif (coverage == "full" or x*y*z <= MAX_VOXELS) and x*y*z > 0 then
                    queue[#queue + 1] = {shape = shape, x = x, y = y, z = z,
                        scale = scale, planes = planes, row = 0, vehicle = a.vehicle,
                        full = coverage == "full"}
                else batchSkipped = batchSkipped + 1 end
            end
        end
    end
    tell("Vehicle: " .. #queue .. " shapes; skipped " .. batchSkipped)
end

local function startJob(job)
    if not valid(job.shape) then return false end
    local x, y, z, scale = GetShapeSize(job.shape)
    if x ~= job.x or y ~= job.y or z ~= job.z or scale ~= job.scale then return false end
    local old = records[job.shape]
    if old and old.fullyHidden then return false end
    local source = old and old.proxy or job.shape
    if not valid(source) then return false end
    job.voxelCount = GetShapeVoxelCount(job.shape)
    job.bodyAtStart = GetShapeBody(job.shape)
    if job.full then job.row = job.y * job.z; return true end
    -- A separate static body avoids changing the original body's mass/center of mass.
    local xml = '<body dynamic="false"><voxbox size="1 1 1" scale="' ..
        tostring(job.scale / 0.1) .. '" material="wood" tags="section_proxy invisible unbreakable"/></body>'
    local entities = Spawn(xml, GetShapeWorldTransform(job.shape), true, false)
    for _, entity in ipairs(entities) do
        if GetEntityType(entity) == "body" then job.body = entity end
        if GetEntityType(entity) == "shape" then job.proxy = entity end
    end
    if not valid(job.body) or not valid(job.proxy) then
        for _, entity in ipairs(entities) do if valid(entity) then Delete(entity) end end
        return false
    end
    SetShapeCollisionFilter(job.proxy, 0, 0)
    CopyShapePalette(source, job.proxy)
    CopyShapeContent(source, job.proxy)
    SetShapeLocalTransform(job.proxy, Transform())
    local _, _, _, newScale = GetShapeSize(job.proxy)
    if math.abs(newScale - job.scale) > 0.00001 then
        Delete(job.body)
        return false -- Never display a mismatched scale.
    end
    job.voxelCount = GetShapeVoxelCount(job.shape)
    job.bodyAtStart = GetShapeBody(job.shape)
    return true
end

local function processQueue()
    local budget = ROWS_PER_TICK
    -- Starting at most one clone per tick bounds allocation spikes.
    if not active and #queue > 0 then
        local job = table.remove(queue, 1)
        if startJob(job) then active = job else batchSkipped = batchSkipped + 1 end
    end
    local job = active
    if not job then return end
    if not valid(job.shape) or GetShapeVoxelCount(job.shape) ~= job.voxelCount
        or GetShapeBody(job.shape) ~= job.bodyAtStart then
        if valid(job.body) then Delete(job.body) end
        active = nil
        batchSkipped = batchSkipped + 1
        return
    end
    SetBrush("cube", 1, 0)
    while budget > 0 and job.row < job.y * job.z do
        local y, z = job.row % job.y, math.floor(job.row / job.y)
        local first, last = SectionClip.row(job.planes, y, z, job.x)
        if first then DrawShapeBox(job.proxy, first, y, z, last, y, z) end
        job.row, budget = job.row + 1, budget - 1
        if not valid(job.proxy) then job.row = job.y * job.z; break end
    end
    if job.row == job.y * job.z then
        local old = records[job.shape]
        local hadNoShadow = HasTag(job.shape, "noshadow")
        if old then hadNoShadow = old.hadNoShadow end
        if old and valid(old.body) then Delete(old.body) end
        local fullyHidden = job.full or not valid(job.proxy) or GetShapeVoxelCount(job.proxy) == 0
        if fullyHidden then
            if valid(job.body) then Delete(job.body) end
        else SetBodyTransform(job.body, GetShapeWorldTransform(job.shape)) end
        SetTag(job.shape, "invisible")
        SetTag(job.shape, "noshadow")
        SetTag(job.shape, "section_original", tostring(job.shape))
        if not fullyHidden then RemoveTag(job.proxy, "invisible") end
        records[job.shape] = {body = job.body, proxy = job.proxy,
            fullyHidden = fullyHidden, hadNoShadow = hadNoShadow,
            count = job.voxelCount, originalBody = job.bodyAtStart, vehicle = job.vehicle}
        active, batchDone = nil, batchDone + 1
        if #queue == 0 then
            tell("Section complete: " .. batchDone .. "; skipped: " .. batchSkipped)
        end
    end
end

local function maintainProxies()
    local stale = {}
    for shape, r in pairs(records) do
        if not valid(shape) or (not r.fullyHidden and (not valid(r.body) or not valid(r.proxy))) then
            stale[#stale + 1] = shape
        elseif GetShapeVoxelCount(shape) ~= r.count or GetShapeBody(shape) ~= r.originalBody then
            -- Never keep an obsolete visual shell after physical destruction.
            stale[#stale + 1] = shape
        elseif not r.fullyHidden then
            SetBodyTransform(r.body, GetShapeWorldTransform(shape))
        end
    end
    for _, shape in ipairs(stale) do restore(shape) end
end

function init()
    RegisterTool(TOOL, "Section Tool", "MOD/tool.xml", 6)
    SetBool("game.tool." .. TOOL .. ".enabled", true)
end

function tick(dt)
    targetRefresh = targetRefresh - dt
    messageTime = math.max(0, messageTime - dt)
    maintainProxies()
    if equipped() and not GetBool("game.player.canusetool") then
        aim = nil
    elseif equipped() then
        if InputDown("q") then angle = angle - 45 * dt end
        if InputDown("e") then angle = angle + 45 * dt end
        angle = (angle + 180) % 360 - 180
        if InputPressed("c") then side = -side end
        aim = getAim()
        if InputPressed("r") then restoreAll()
        elseif InputPressed("rmb") then
            -- Query the original collision mesh, including the invisible half.
            -- Cancel pending cuts so they cannot re-hide a just-restored shape.
            cancelJob()
            local record = aim.hit and records[aim.shape]
            local vehicle = record and record.vehicle or 0
            if aim.hit and vehicle == 0 then vehicle = SectionVehicle.resolve(aim.shape) end
            if vehicle ~= 0 then
                local list = {}
                for s,r in pairs(records) do if r.vehicle == vehicle then list[#list+1]=s end end
                for _,s in ipairs(list) do restore(s) end
                tell("Vehicle restored: " .. #list .. " shapes")
            else tell("Aim at a TABS vehicle to restore") end
        elseif InputPressed("usetool") then enqueue(aim) end
        SetToolTransform(Transform(Vec(0.3, -0.3, -0.6)))
    else aim = nil end
    processQueue()
    if aim then
        local a, b = point(aim, 0, -GUIDE_LENGTH/2, 0), point(aim, 0, GUIDE_LENGTH/2, 0)
        DrawLine(a, b, 0.2, 0.9, 1, 1)
        DrawLine(aim.origin, point(aim, side, 0, 0), 1, 0.65, 0.15, 1)
        if aim.hit and records[aim.shape] then DrawShapeOutline(aim.shape, 0.2, 1, 0.6, 0.8) end
    end
end

function draw()
    if not equipped() then return end
    -- HUD overlay keeps the section line readable when the wall occludes world lines.
    if aim then
        local ax, ay = UiWorldToPixel(point(aim, 0, -GUIDE_LENGTH/2, 0))
        local bx, by = UiWorldToPixel(point(aim, 0, GUIDE_LENGTH/2, 0))
        local dx, dy = bx-ax, by-ay
        UiPush()
        UiTranslate((ax+bx)/2, (ay+by)/2)
        UiRotate(-math.deg(math.atan2(dy, dx)))
        UiAlign("center middle")
        UiColor(0.2, 0.9, 1, 1)
        UiRect(math.sqrt(dx*dx+dy*dy), 3)
        UiPop()
    end
    UiPush()
    UiTranslate(24, UiHeight() - 110)
    UiFont("regular.ttf", 20)
    UiTextShadow(0, 0, 0, 1, 2)
    local lines = {
        string.format("%s | %s | angle %.0f",
            aim and aim.hit and aim.vehicle ~= 0 and "TABS VEHICLE" or "AIM AT TABS VEHICLE",
            side == 1 and "RIGHT" or "LEFT", angle),
        "LMB: section vehicle   RMB: restore vehicle   R: restore all / cancel",
        "Q/E: rotate   C: side"
    }
    if active or #queue > 0 then
        lines[#lines+1] = "Processing: " .. (#queue + (active and 1 or 0)) .. " shapes remaining"
    elseif messageTime > 0 then lines[#lines+1] = message end
    for _, text in ipairs(lines) do UiText(text); UiTranslate(0, 26) end
    UiPop()
end
