-- Player-only filtering. Dedicated layers mirror original layer semantics;
-- masks are translated so every shape-to-shape collision pair is preserved.
SectionCollision = {vehicles = {}, targets = {}, entries = {}, mapping = {}}
local C = SectionCollision
local BACKUP, TARGET = "section_player_filter", "section_player_target"
local bits = {1,2,4,8,16,32,64,128}
local function valid(h) return h and h ~= 0 and IsHandleValid(h) end
local function has(n,b) return math.floor(n/b)%2 == 1 end
local function intersects(a,b)
    for _,bit in ipairs(bits) do if has(a,bit) and has(b,bit) then return true end end
    return false
end
local function clear(n,b) return has(n,b) and n-b or n end
local function saved(s)
    local l,m = GetTagValue(s,BACKUP):match("^(%d+) (%d+)$")
    return tonumber(l),tonumber(m)
end
local function capture()
    local alive = {}
    for _,s in ipairs(FindShapes("",true)) do
        alive[s] = true
        local l,m = GetShapeCollisionFilter(s)
        local e = C.entries[s]
        if not e then
            local oldL,oldM = saved(s)
            e = {layer=oldL or l, mask=oldM or m, appliedL=l, appliedM=m}
            C.entries[s] = e
            local v = tonumber(GetTagValue(s,TARGET))
            if v and C.vehicles[v] then C.targets[s]=v end
        elseif l ~= e.appliedL or m ~= e.appliedM then
            -- Respect an external script's newly supplied filter.
            e.layer,e.mask = l,m
        end
    end
    for s in pairs(C.entries) do
        if not alive[s] then C.entries[s]=nil; C.targets[s]=nil end
    end
end
local function revert()
    capture()
    for s,e in pairs(C.entries) do
        SetShapeCollisionFilter(s,e.layer,e.mask)
        RemoveTag(s,BACKUP); RemoveTag(s,TARGET)
    end
    if C.playerMask ~= nil then
        local current = GetPlayerParam("CollisionMask")
        if current == C.appliedPlayerMask then SetPlayerParam("CollisionMask",C.playerMask) end
    end
    C.entries,C.targets,C.vehicles,C.mapping = {},{},{},{}
    C.playerMask,C.appliedPlayerMask = nil,nil
end
local function rebuild()
    capture()
    local used, needed, mapping = {},{},{}
    for s,e in pairs(C.entries) do
        for _,bit in ipairs(bits) do if has(e.layer,bit) then used[bit]=true end end
        if C.targets[s] and C.vehicles[C.targets[s]] and e.layer ~= 0 then needed[e.layer]=true end
    end
    local layers = {}
    for l in pairs(needed) do layers[#layers+1]=l end
    table.sort(layers)
    for _,l in ipairs(layers) do
        for i=#bits,1,-1 do
            local bit=bits[i]
            if not used[bit] then mapping[l]=bit; used[bit]=true; break end
        end
        if not mapping[l] then
            revert()
            return false, "Player pass-through unavailable: collision layers are occupied"
        end
    end
    local current = GetPlayerParam("CollisionMask")
    if C.playerMask == nil or current ~= C.appliedPlayerMask then C.playerMask=current end
    local playerMask = C.playerMask
    for _,bit in pairs(mapping) do playerMask=clear(playerMask,bit) end
    for s,e in pairs(C.entries) do
        local l,m = e.layer,e.mask
        for original,bit in pairs(mapping) do
            m=clear(m,bit)
            if intersects(e.mask,original) then m=m+bit end
        end
        local vehicle = C.targets[s]
        if vehicle and C.vehicles[vehicle] then
            l=mapping[e.layer] or e.layer
            SetTag(s,TARGET,tostring(vehicle))
        else RemoveTag(s,TARGET) end
        if l ~= e.layer or m ~= e.mask then
            SetTag(s,BACKUP,string.format("%d %d",e.layer,e.mask))
        else RemoveTag(s,BACKUP) end
        if l ~= e.appliedL or m ~= e.appliedM then SetShapeCollisionFilter(s,l,m) end
        e.appliedL,e.appliedM=l,m
    end
    C.mapping=mapping
    C.appliedPlayerMask=playerMask
    SetPlayerParam("CollisionMask",playerMask)
    return true
end
function C.enable(vehicle,shapes)
    if C.vehicles[vehicle] then return true end
    C.vehicles[vehicle]=true
    for _,s in ipairs(shapes) do
        if valid(s) and not HasTag(s,"section_proxy") then C.targets[s]=vehicle end
    end
    return rebuild()
end
function C.restore(vehicle)
    if not next(C.vehicles) and not next(C.entries) then return end
    if not vehicle then revert(); return end
    C.vehicles[vehicle]=nil
    for s,v in pairs(C.targets) do if v==vehicle then C.targets[s]=nil end end
    if next(C.vehicles) then rebuild() else revert() end
end
function C.tick()
    if not next(C.vehicles) then return end
    for v in pairs(C.vehicles) do if not valid(v) then C.vehicles[v]=nil end end
    if not next(C.vehicles) then revert(); return end
    return rebuild()
end
function C.query(fn) return fn() end -- Nonzero layers remain normally raycastable.
function C.init()
    -- Migrate any surviving backup tags from the withdrawn all-object version.
    for _,s in ipairs(FindShapes("section_collision_backup",true)) do
        local _,l,m=GetTagValue(s,"section_collision_backup"):match("^(%d+) (%d+) (%d+)$")
        if l then SetShapeCollisionFilter(s,tonumber(l),tonumber(m)) end
        RemoveTag(s,"section_collision_backup")
    end
end
