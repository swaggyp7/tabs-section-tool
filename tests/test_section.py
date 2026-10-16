"""Run with Python + lupa (Lua 5.1). Does not replace in-game testing."""
import math
import random
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / '.tools/python'))
from lupa.lua51 import LuaRuntime

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute((ROOT / 'clip.lua').read_text())
random.seed(4827)
checks = 0
for _ in range(1000):
    size = random.randint(1, 80)
    y, z = random.randrange(40), random.randrange(40)
    planes = []
    for i in range(3):
        a, b, c = [random.uniform(-2, 2) for _ in range(3)]
        if random.random() < .25:
            a = 0
        lo = random.uniform(-30, 20)
        planes.append(dict(a=a, b=b, c=c, d=random.uniform(-10, 10), lo=lo, hi=lo+random.uniform(.1, 40)))
    expected = [x for x in range(size) if all(
        p['lo'] - 1e-8 <= p['a']*(x+.5)+p['b']*(y+.5)+p['c']*(z+.5)+p['d'] <= p['hi']+1e-8
        for p in planes)]
    result = lua.globals().SectionClip.row(lua.table_from([lua.table_from(p) for p in planes]), y, z, size)
    actual = [] if result is None else list(range(result[0], result[1]+1))
    assert actual == expected, (planes, expected, actual)
    checks += 1

# Verify camera-oriented half spaces at common and oblique angles, both sides.
for angle in (0, 30, 90, 135, 180, -45):
    for side in (-1, 1):
        a = math.radians(angle)
        planes = [dict(a=math.cos(a), b=-math.sin(a), c=0, d=0,
                       lo=min(0, side*100), hi=max(0, side*100))]
        for y in range(8):
            expected = [x for x in range(8) if min(0,side*100)-1e-8 <=
                        math.cos(a)*(x+.5)-math.sin(a)*(y+.5) <= max(0,side*100)+1e-8]
            r = lua.globals().SectionClip.row(lua.table_from([lua.table_from(p) for p in planes]), y, 0, 8)
            assert ([] if r is None else list(range(r[0], r[1]+1))) == expected
            checks += 1

lua.execute((ROOT / 'tests/engine_mock.lua').read_text())
lua.execute((ROOT / 'vehicle.lua').read_text())
lua.execute((ROOT / 'collision.lua').read_text())
source = (ROOT / 'main.lua').read_text().replace('#include "clip.lua"', '').replace('#include "vehicle.lua"', '').replace('#include "collision.lua"', '')
lua.execute(source)  # Compiles the full mod as Lua 5.1.
lua.execute('''
entities[2].vehicle=9000
entities[9000]={kind="vehicle",body=2,tags={TABS=""}}
init()
press("usetool")
assert(HasTag(1, "invisible"), "original must be hidden")
assert(GetShapeVoxelCount(1) == 192, "original voxels must remain")
assert(proxyCount() == 96, "right half should be removed from visual proxy")
assert(originalWrites == 0, "never edit original voxels")
press("c")
press("usetool")
assert(proxyCount() == 0, "second opposite cut should accumulate")
press("rmb")
assert(not HasTag(1, "invisible"), "right click restores")
assert(proxyBodies() == 0, "right click cleans helpers")
SetTag(1, "noshadow")
press("usetool")
press("r")
assert(HasTag(1, "noshadow"), "preserve pre-existing tags")
RemoveTag(1, "noshadow")
press("usetool")
entities[3] = {kind="shape", body=2, tags={invisible="", noshadow="", section_original="1"},
    pos=Vec(), size={1,1,1}, scale=.1, voxels={}}
entities[1].voxels["0,0,0"] = nil
tick(.016)
assert(not HasTag(1, "invisible"), "destruction restores original")
assert(not HasTag(3, "invisible"), "destruction restores inherited fragments")
assert(proxyBodies() == 0)
press("usetool")
entities[1].pos = Vec(5, 6, 7)
tick(.016)
for _, e in pairs(entities) do
    if e.helper and e.kind == "body" then assert(e.pos[1] == 5 and e.pos[2] == 6) end
end
press("r")
-- A large shape takes multiple ticks. Cancellation must leave original visible.
entities[1].size = {8, 100, 100}
entities[1].pos = Vec(-.4, -.3, -5.4)
press("usetool")
assert(not HasTag(1, "invisible"), "no partial commit during processing")
press("r")
assert(not HasTag(1, "invisible") and proxyBodies() == 0, "cancel cleans work in progress")
assert(originalWrites == 0)
''')
lua.execute('''
-- A modular vehicle larger than the old 96-shape limit. Detached unphysical
-- tracks sit in front of the hit surface, and another component is >20m behind it.
entities[1].size={8,6,4}
entities[2].vehicle=9000
entities[2].pos=Vec(0,0,-5)
entities[9000]={kind="vehicle",body=2,tags={TABS=""}}
for i=1,140 do
    local b,s=10000+i*2,10001+i*2
    entities[b]={kind="body",vehicle=9000,pos=Vec(.1,0,-5),tags={}}
    entities[s]={kind="shape",body=b,pos=Vec(.1,0,i==140 and -40 or -5),
        tags={},size={1,1,1},scale=.1,voxels={["0,0,0"]=1}}
end
entities[11000]={kind="body",pos=Vec(.1,0,-4),tags={}}
entities[11001]={kind="shape",body=11000,pos=Vec(.1,0,-4),tags={},material="unphysical",
    size={1,1,1},scale=.1,voxels={["0,0,0"]=1}}
entities[11002]={kind="body",pos=Vec(.2,0,-4),tags={}}
entities[11003]={kind="shape",body=11002,pos=Vec(.2,0,-4),tags={},material="metal",
    size={1,1,1},scale=.1,voxels={["0,0,0"]=1}}
function QueryAabbShapes() return {1,11001,11003} end
press("c") -- Earlier tests left the tool in LEFT mode; select RIGHT.
press("usetool")
for i=1,150 do tick(.016) end
for i=1,140 do assert(HasTag(10001+i*2,"invisible"), "all modules beyond 96 must be processed") end
assert(HasTag(11001,"invisible"), "detached front track must be included")
assert(not HasTag(11003,"invisible"), "nearby scenery must be excluded")
assert(GetShapeVoxelCount(11001)==1, "original track remains intact")
press("rmb")
for i=1,140 do assert(not HasTag(10001+i*2,"invisible"), "right click restores entire vehicle") end
assert(not HasTag(11001,"invisible"))
-- Directly aiming an independent track must identify the same vehicle.
assert(SectionVehicle.resolve(11001)==9000)
function QueryRaycast() return true,5,Vec(0,0,1),11001 end
press("usetool")
for i=1,150 do tick(.016) end
assert(HasTag(10281,"invisible"), "aiming track sections entire vehicle")
press("rmb")
assert(not HasTag(10281,"invisible"), "track aim restores entire vehicle")
-- Ordinary objects and non-TABS vehicles must remain untouched.
entities[11004]={kind="shape",body=11002,pos=Vec(.2,0,-4),tags={},material="metal",
    size={1,1,1},scale=.1,voxels={["0,0,0"]=1}}
assert(SectionVehicle.resolve(11003)==0)
function QueryRaycast() return true,5,Vec(0,0,1),11003 end
press("usetool")
for i=1,5 do tick(.016) end
assert(not HasTag(11003,"invisible"), "ordinary object is not supported")
assert(not HasTag(11004,"invisible"), "same-body neighbor is untouched")
assert(not HasTag(11001,"invisible"), "nearby vehicle track is untouched")
assert(not HasTag(1,"invisible"), "nearby vehicle is untouched")
press("rmb")
assert(not HasTag(11003,"invisible"))
entities[9001]={kind="vehicle",body=11002,tags={}}
entities[11002].vehicle=9001
assert(SectionVehicle.resolve(11003)==0, "non-TABS vehicle must be rejected")
press("usetool")
for i=1,5 do tick(.016) end
assert(not HasTag(11003,"invisible"), "non-TABS vehicle remains visible")
''')
print(f'PASS: {checks} clipping cases; Lua 5.1 compilation; cut/recut/restore, tags, fragments, movement, cancellation.')
print('PASS: 140-module TABS vehicle; detached-track recognition and restore; ordinary objects and non-TABS vehicles rejected.')
print('Engine behavior and visual rendering still require in-game verification.')

# Collision semantics are verified on all shape pairs, not just the terrain.
lua.execute('''
function overlap(a,b)
    for i=0,7 do
        local bit=2^i
        if math.floor(a/bit)%2==1 and math.floor(b/bit)%2==1 then return true end
    end
    return false
end
function collides(a,b)
    local al,am=GetShapeCollisionFilter(a)
    local bl,bm=GetShapeCollisionFilter(b)
    return overlap(al,bm) and overlap(bl,am)
end
function physicsSnapshot()
    local shapes=FindShapes("",true)
    local result={}
    for _,a in ipairs(shapes) do for _,b in ipairs(shapes) do
        result[a..":"..b]=collides(a,b)
    end end
    return result
end
function verifyPhysics(before)
    for key,value in pairs(before) do
        local a,b=key:match("^(%d+):(%d+)$")
        assert(collides(tonumber(a),tonumber(b))==value,"physics changed for "..key)
    end
end
function QueryRaycast() return true,5,Vec(0,0,1),1 end
SetShapeCollisionFilter(1,4,251)
SetShapeCollisionFilter(11001,8,239)
SetShapeCollisionFilter(10003,16,247)
SetShapeCollisionFilter(11003,1,255)
local before=physicsSnapshot()
press("usetool")
for i=1,150 do tick(.016) end
verifyPhysics(before)
assert(SectionCollision.vehicles[9000],"section must automatically enable player pass-through")
for _,s in ipairs({1,11001,10003}) do
    local layer=GetShapeCollisionFilter(s)
    assert(layer~=0,"physical collision must not be disabled")
    assert(not overlap(layer,GetPlayerParam("CollisionMask")),"player must ignore vehicle")
end
assert(overlap(GetShapeCollisionFilter(11003),GetPlayerParam("CollisionMask")),"player still collides with other objects")
local mask=GetPlayerParam("CollisionMask")
press("n")
assert(GetPlayerParam("CollisionMask")==mask,"N must no longer toggle anything")
press("rmb")
local l,m=GetShapeCollisionFilter(1)
assert(l==4 and m==251 and GetPlayerParam("CollisionMask")==255)
verifyPhysics(before)
-- More than one sectioned vehicle: restoring one must not restore the other.
entities[9001].tags.TABS=""
local ok=SectionCollision.enable(9000,{1,11001,10003})
assert(ok)
assert(SectionCollision.enable(9001,{11003}))
verifyPhysics(before)
SectionCollision.restore(9000)
assert(overlap(GetShapeCollisionFilter(1),GetPlayerParam("CollisionMask")))
assert(not overlap(GetShapeCollisionFilter(11003),GetPlayerParam("CollisionMask")))
verifyPhysics(before)
SectionCollision.restore()
verifyPhysics(before)
-- Custom player mask is restored, too.
SetPlayerParam("CollisionMask",127)
assert(SectionCollision.enable(9000,{1}))
SectionCollision.restore()
assert(GetPlayerParam("CollisionMask")==127)
SetPlayerParam("CollisionMask",255)
-- Inherited fragments must recover the original filter on restore.
assert(SectionCollision.enable(9000,{1}))
local l,m=GetShapeCollisionFilter(1)
entities[13000]={kind="shape",body=2,pos=Vec(),size={1,1,1},scale=.1,voxels={},layer=l,mask=m,
 tags={section_player_filter=GetTagValue(1,"section_player_filter"),section_player_target="9000"}}
SectionCollision.tick()
assert(not overlap(GetShapeCollisionFilter(13000),GetPlayerParam("CollisionMask")))
SectionCollision.restore()
l,m=GetShapeCollisionFilter(13000)
assert(l==4 and m==251)
-- Layer exhaustion must fail safely, retaining every physical collision.
SetShapeCollisionFilter(13000,255,255)
local all=physicsSnapshot()
assert(not SectionCollision.enable(9000,{1}))
verifyPhysics(all)
assert(GetPlayerParam("CollisionMask")==255 and GetShapeCollisionFilter(1)==4)
Delete(13000)
-- R always restores both geometry and player collision.
press("usetool")
for i=1,150 do tick(.016) end
assert(SectionCollision.vehicles[9000])
press("r")
assert(GetPlayerParam("CollisionMask")==255 and not HasTag(1,"invisible"))
verifyPhysics(before)
''')
print('PASS: automatic player-only pass-through; every physical collision pair preserved; multi-vehicle restore; custom player mask; fragments; exhausted layers; N removed; R/RMB restore.')
