entities = {}
originalWrites = 0
local keys, nextId = {}, 10
function Vec(x,y,z) return {x or 0,y or 0,z or 0} end
function VecAdd(a,b) return Vec(a[1]+b[1],a[2]+b[2],a[3]+b[3]) end
function VecSub(a,b) return Vec(a[1]-b[1],a[2]-b[2],a[3]-b[3]) end
function VecScale(a,n) return Vec(a[1]*n,a[2]*n,a[3]*n) end
function VecDot(a,b) return a[1]*b[1]+a[2]*b[2]+a[3]*b[3] end
function VecLength(a) return math.sqrt(VecDot(a,a)) end
function Transform(p) return {pos=p or Vec()} end
function TransformToParentVec(t,v) return v end
function TransformToLocalVec(t,v) return v end
function GetCameraTransform() return Transform() end
function IsHandleValid(h) return entities[h] ~= nil end
function GetEntityType(h) return entities[h].kind end
function GetShapeBody(h) return entities[h].body end
function GetBodyVehicle(b) return entities[b].vehicle or 0 end
function GetEntityParent() return 0 end
function IsBodyDynamic() return false end
function GetJointedBodies(b) return {b} end
function GetBodyShapes(b)
    local r={}; for h,e in pairs(entities) do if e.kind=="shape" and e.body==b then r[#r+1]=h end end; return r
end
function GetVehicleBody(v) return entities[v].body end
function GetEntityChildren(v)
    local r={}; for h,e in pairs(entities) do
        if e.kind=="shape" and entities[e.body].vehicle==v then r[#r+1]=h end
    end; return r
end
function GetBodyBounds(b)
    local p=entities[b].pos
    return VecSub(p,Vec(.5,.5,.5)),VecAdd(p,Vec(.5,.5,.5))
end
function FindVehicles(tag)
    local r={}; for h,e in pairs(entities) do if e.kind=="vehicle" and HasTag(h,tag) then r[#r+1]=h end end; return r
end
function QueryRequire() end
function GetShapePalette() return {1} end
function GetShapeMaterial(h) return entities[h].material or "metal" end
function GetShapeMaterialAtIndex(h,x,y,z)
    return entities[h].voxels[x..","..y..","..z] and (entities[h].material or "metal") or ""
end
function GetShapeWorldTransform(h)
    local e=entities[h]
    return Transform(e.helper and entities[e.body].pos or e.pos)
end
function GetShapeSize(h) local e=entities[h]; return e.size[1],e.size[2],e.size[3],e.scale end
function GetShapeVoxelCount(h) local n=0; for _ in pairs(entities[h].voxels) do n=n+1 end; return n end
function HasTag(h,k) return entities[h].tags[k] ~= nil end
function GetTagValue(h,k) return entities[h].tags[k] or "" end
function SetTag(h,k,v) entities[h].tags[k]=v or "" end
function RemoveTag(h,k) entities[h].tags[k]=nil end
function FindShapes(tag)
    local r={}; for h,e in pairs(entities) do if e.kind=="shape" and (tag=="" or HasTag(h,tag)) then r[#r+1]=h end end; return r
end
local playerMask=255
function GetPlayerParam(p) assert(p=="CollisionMask"); return playerMask end
function SetPlayerParam(p,v) assert(p=="CollisionMask"); playerMask=v end
function SetBodyTransform(h,t) entities[h].pos=t.pos end
function SetShapeLocalTransform() end
function SetShapeCollisionFilter(h,layer,mask) entities[h].layer=layer; entities[h].mask=mask end
function GetShapeCollisionFilter(h)
    return entities[h].layer or 1, entities[h].mask or 255
end
function CopyShapePalette() end
function CopyShapeContent(src,dst)
    local s,d=entities[src],entities[dst]; d.size={unpack(s.size)}; d.voxels={}
    for k,v in pairs(s.voxels) do d.voxels[k]=v end
end
function Spawn(xml,t)
    local b,s=nextId,nextId+1; nextId=nextId+2
    entities[b]={kind="body",pos=t.pos,tags={},helper=true}
    entities[s]={kind="shape",body=b,tags={section_proxy="",invisible=""},helper=true,
        size={1,1,1},scale=tonumber(xml:match('scale="([%d%.]+)"'))*.1,voxels={}}
    return {b,s}
end
function Delete(h)
    if entities[h] and entities[h].kind=="body" then
        local ids={}; for id,e in pairs(entities) do if e.body==h then ids[#ids+1]=id end end
        for _,id in ipairs(ids) do entities[id]=nil end
    end
    entities[h]=nil
end
function SetBrush(kind,size,index) assert(kind=="cube" and size==1 and index==0) end
function DrawShapeBox(h,x0,y0,z0,x1,y1,z1)
    if h==1 then originalWrites=originalWrites+1 end
    for x=x0,x1 do for y=y0,y1 do for z=z0,z1 do entities[h].voxels[x..","..y..","..z]=nil end end end
end
function QueryRaycast() return true,5,Vec(0,0,1),1 end
function QueryAabbShapes() return {1} end
function QueryRejectBody() end
function GetToolBody() return 0 end
function GetPlayerVehicle() return 0 end
function GetString() return "reversible_section_tool" end
function GetBool() return true end
function SetBool() end
function RegisterTool() end
function SetToolTransform() end
function InputPressed(k) return keys[k] or false end
function InputDown(k) return keys[k] or false end
function DrawLine() end
function DrawShapeOutline() end
function press(k) keys={[k]=true}; tick(.016); keys={} end
function proxyCount()
    local n=0; for h,e in pairs(entities) do if e.kind=="shape" and e.helper then n=n+GetShapeVoxelCount(h) end end; return n
end
function proxyBodies()
    local n=0; for _,e in pairs(entities) do if e.kind=="body" and e.helper then n=n+1 end end; return n
end
entities[2]={kind="body",pos=Vec(),tags={}}
entities[1]={kind="shape",body=2,pos=Vec(-.4,-.3,-5.4),tags={},size={8,6,4},scale=.1,voxels={}}
for x=0,7 do for y=0,5 do for z=0,3 do entities[1].voxels[x..","..y..","..z]=1 end end end
