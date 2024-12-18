--[[
Copyright (c) 2020 Boris Marmontel

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
]]


-- local Monster = require 'autogen_zombie'
-- 
-- function Monster:stepDigEndCallback(entity)
--     self.rect = rect[1]
--     self.leader_effect:createMinions(self, entity)
-- end




local MonsterFallState = require 'monster_fall_state'
local MonsterJumpState = require 'monster_jump_state'
local class = require 'middleclass'
local Monster = require 'monster_toolbox'
local MonsterLeaderEffect = require 'monster_leader_effect'
local Snapshot = require 'monster_snapshot_minimal'

local State = {
    Idle = 0,
    Wait = 1,
    Move = 2,
    GetHit = 3,
    Fall = 4,
    Getup = 5,
    Attack = 6,
    Attack2 = 7,
    JumpStart = 8,
    JumpAir = 9,
    JumpEnd = 10,
    Dig = 11,
    Hidden = 12,
    TakeOut = 13,
    Die = 14
}

local Animations = {
    [State.Idle] = "idle",
    [State.Wait] = "idle",
    [State.Move] = "move",
    [State.GetHit] = "hit",
    [State.Fall] = "fall",
    [State.Getup] = "getup",
    [State.Attack] = "attack",
    [State.Attack2] = "vomit",
    [State.JumpStart] = "jump_start",
    [State.JumpAir] = "jumping",
    [State.JumpEnd] = "jumping",
    [State.Dig] = "dig",
    [State.Hidden] = nil,
    [State.TakeOut] = "spawn",
    [State.Die] = "die"
}

local RenderConfig = Monster.initRenderConfig(
    "monster_zombie",
    "pc_palette_monster_zombie")

local rect = {
    Rect:new(0, 0, 28, 44),
    Rect:new(0, 0, 28*2, 44*2),
    Rect:new(0, 0, 28*3, 44*3)
}
local rect_hidden = {
    Rect:new(0, 43, 28, 44),
    Rect:new(0, 87, 28*2, 44*2),
    Rect:new(0, 131, 28*3, 44*3)
}

local BrainAI = class('BrainAI')
local MonsterZombie = class('MonsterZombie')

local gravity = MonsterJumpState.gravity

function MonsterZombie:initialize()
    self.states = State
    
    self.frame = 0.0
    self.state = State.Idle
    self.scalex = 1.0
    self.size = 0
    self.rect = rect[self.size+1]
    
    self.inputs = Input:new()
    self.inputs1 = 0
    self.inputs2 = 0
    
    self.jump_timer = 0.0
    self.long_jump = false
    self.ground_timer = 0.0
    
    self.leader_effect = nil
    self.is_leader = false
    self.dig_allowed = false
    self.bullet_launch = false
        
    self.jump_state = MonsterJumpState:new(
        State.Idle, State.JumpStart, State.JumpAir, 3.0,
        MonsterJumpState.twoFrameAnim(0,1))
    
    self.fall_state = MonsterFallState:new(
        State.Idle, State.GetHit, State.Fall, State.Getup,
        4,9,5, 2,3,5)
    
    self.prev_snap = Snapshot:new()
end

function MonsterZombie:evCreate(entity, param)
    
    if(param.special_spawn) then
        self.state = State.TakeOut
    end
    
    Monster.evCreate(self, entity, param, BrainAI)
    
    if(param.preview and self.size > 1) then
        self.size = 1
    end
    
    self.leader_effect = MonsterLeaderEffect:new(
        self.is_leader, State.Dig, State.Hidden, State.TakeOut)
    
    if(self.leader_effect ~= nil) then
        return
    end

    if(math.random() < 0.25) then
        self.dig_allowed = true
    end

    
    --entity:makeBrainKeyboard()
end

function MonsterZombie:updateBbox()
    if(self.state == State.Hidden) then
        self.rect = rect_hidden[self.size+1]
    else
        self.rect = rect[self.size+1]
    end
end

function MonsterZombie:setState(entity, state)
    self.state = state
    self.frame = 0.0
    
    if(self.state == State.Attack) then
        entity:soundPlay("attack", entity.pos)
    
    elseif(state == State.Attack2) then
        local box = entity:boundingBox()
        pcCreateAttackIcon(entity:getContext(), Vec2:new(box:center().x, box.y1 + 10))
    
    elseif(state == State.Hidden or state == State.TakeOut) then
        self:updateBbox()
    end
end

function MonsterZombie:render(entity, r)
    Monster.render(self, entity, r, Animations, RenderConfig)
end

function MonsterZombie:update(entity, dt)
    if(not entity:alive()) then
        Monster.destroyOnAnimationEnd(self, entity, 9.0, 0.22, dt)
        
        entity:updateLandPhysics(
            dt, gravity, Vec2:new(), Vec2:new(0.05,0), 0.2, true, false)
        return
    end
    
    -- damagezone example
--     if(false) then
--         local dmg = Damage:new()
--         dmg:set(DamageType.Blunt, 10)
--         dmg.force = HitForce:new(Vec2:new(self.scalex*5,-5))
-- 
--         local hitbox = entity:boundingBoxRelative()
--         local w = entity:boundingBox():center()
--         local dz = DamageZoneBase:new(
--             --entity:getAttackDamages(0),
--             dmg,
--             entity:targetType(),
--             w, true, false)
--         local hit = dz:hurt(entity:getContext(), hitbox, entity.pos, entity, true, false)
--     end
    
    -- netplay client update

    if(entity:remote()) then
        local prev_snap, last_snap = Monster.netplayClientUpdate2(self, entity)
        if(last_snap ~= nil) then
        
            if(prev_snap ~= nil and prev_snap.state ~= last_snap.state) then
                if(self.state == State.Attack) then
                    entity:soundPlay("attack", entity.pos)
                end
                self.bullet_launch = false
            end
            if(self:shouldInflictDamages(self.state, self.frame)) then
                local hitbox = self:hitbox(self.state, entity)
                if(self.state == State.Attack) then
                    entity:inflictDamages(self.state, 0, self.scalex, -1, self.size/2.0 + 1)
                elseif(self.state == State.Attack2) then
                    MonsterZombie:createVomit(entity, self.bullet_launch ,self.scalex, entity:status())
                    if (self.bullet_launch == false) then
                        entity:soundPlay("vomit_thing", entity.pos);
                    end
                    self.bullet_launch = true;
                end
            end
        end
        return
    end
    
    
    
    if(entity:isPetrified()) then
        entity:updateLandPhysics(
            dt, gravity, Vec2:new(), Vec2:new(0.05,0), 0.2, true, false)
        return
    end
    
    entity:updateBrain(self.inputs, dt)
    self.inputs1 = bit32_bor(self.inputs1, self.inputs:state())
    self.inputs2 = bit32_bor(self.inputs2, self.inputs:ostate())
    
    
    local force = Vec2:new()
    local hspeed = 2.5
    
    local on_ground;
    on_ground, self.ground_timer =
        Monster.updateGroundTimer(entity, self.ground_timer, dt)
    
    self.fall_state:updateTimers(dt)
    if(self.state == State.Idle)
    then
        self.frame = self.frame + 0.12 * dt
        
        if(on_ground)
        then
            if(self.inputs:check(InputKey.Space))
            then
                self:setState(entity, State.JumpStart)
                
            elseif(self.inputs:check(InputKey.MouseLeft))
            then
                if(self.inputs:check(InputKey.Down))
                then
                    self:setState(entity, State.Attack2)
                else
                    self:setState(entity, State.Attack)
                end
            elseif(Monster.checkMovementInput(self))
            then
                self:setState(entity, State.Move)
            elseif(self.inputs:check(InputKey.Action1) and entity:onDiggableGround())
            then
                self:setState(entity, State.Dig)
            end
        else
            self:setState(entity, State.JumpAir)
        end
    elseif(self.state == State.Move)
    then
        self.frame = self.frame + 0.2 * dt
        
        if(on_ground)
        then
            if(self.inputs:check(InputKey.Space))
            then
                self:setState(entity, State.JumpStart)
                
            elseif(self.inputs:check(InputKey.MouseLeft))
            then
                if(self.inputs:check(InputKey.Down))
                then
                    self:setState(entity, State.Attack2)
                else
                    self:setState(entity, State.Attack)
                end
            elseif(self.inputs:check(InputKey.Action1) and entity:onDiggableGround())
            then
                self:setState(entity, State.Dig)
            elseif(Monster.checkMovementInput(self))
            then
            else
                self:setState(entity, State.Idle)
            end
            
            force.x = (1 + self.size/2.0) * entity:speedCoef() * self.scalex
        else
            self:setState(entity, State.JumpAir)
        end
        
    elseif(self.fall_state:update(self, entity, dt, 0.2, Vec2:new()))
    then
    elseif(self.jump_state:update(
        self, entity, self.inputs, entity.vel, self.scalex,
        force, hspeed + self.size/2.0, 0.2, dt))
    then
    elseif(self.state == State.Attack)
    then
        if(self.frame >= 3.0 and self.frame < 4.0)
        then
            self.frame = self.frame + 0.1 * dt
        else
            self.frame = self.frame + 0.2 * dt
        end
        
        if(self.frame > 4 and self.frame < 5)
        then
            entity:inflictDamages(self.state, 0, self.scalex, -1, self.size/2.0 + 1)
        end
        
        if(self.frame >= 8.0) then
            self:setState(entity, State.Idle)
        end
    elseif(self.state == State.Attack2)
    then
        self.frame = self.frame + 0.2 * dt
        if(self.frame >= 7.0 and self.frame < 10.0)
        then
            MonsterZombie:createVomit(entity, self.bullet_launch, self.scalex, entity:status())
            if (self.bullet_launch == false) then
                entity:soundPlay("vomit_thing", entity.pos);
            end
            self.bullet_launch = true;
        end
        
        if(self.frame >= 25.0) then
            self:setState(entity, State.Idle)
            self.bullet_launch = false
        end
        
    elseif(self.state == State.Dig)
    then
        self.frame = self.frame + 0.2 * dt
        if(self.frame >= 24.0)
        then
            if(self.is_leader and self.leader_effect ~= nil) then
                -- smallest mask is required for createMinions
                self.rect = rect[1]
                self.leader_effect:createMinions(self, entity)
            end
            
            -- self.rect is set to rect_hidden here
            self:setState(entity, State.Hidden)
        end
    elseif(self.state == State.Hidden)
    then
        self.frame = self.frame + dt
        
        if(self.is_leader and self.leader_effect ~= nil) then
            if(not self.leader_effect:waitUntilMinionsAreDead(self, entity)) then
                self:setState(entity, State.TakeOut)
            end
        elseif(self.inputs:check(InputKey.MouseLeft)) then
            if(self.frame >= 3 * 60.0)
            then
                self:setState(entity, State.TakeOut)
                
                if(not entity:isPlayerControlable()) then
                    self:takeOutToNewSpawn(entity)
                end
            end
        end
    elseif(self.state == State.TakeOut)
    then
        self.frame = self.frame + 0.15 * dt
        if(self.frame >= 27.0)
        then
            self:setState(entity, State.Idle)
        end
    end
    
    local platforms_solid = not self.inputs:check(InputKey.Control)
    entity:enablePlatforms(platforms_solid)
    entity:updateLandPhysics(
        dt, gravity, force, Vec2:new(0.05,0), 0.2, true,
        self.fall_state:canBounce(self))
    entity:enablePlatforms(false)
end

function MonsterZombie:takeOutToNewSpawn(entity)
    -- find the nearest spawn to the target (if any)
    local focus = entity:getFocus()
    if(focus.valid) then
        local w = focus.box:center()
        local cells = entity:findNearbySpawnsToTargetOnDiggableGround(22,10,Vec2:new(w.x,w.y))
        
        if(#cells > 0) then
            local cell = cells[1]
            entity.pos = cell:coords()
            entity.pos.y = entity.pos.y - self:bbox():height() + 16
        end
        return
    end
    
    -- Respawn at a random possible location
    local cells = entity:findNearbySpawnsOnDiggableGround(22,10)
    if(#cells > 0) then
        local cell = cells[ math.random(#cells) ]
        entity.pos = cell:coords()
        entity.pos.y = entity.pos.y - self:bbox():height() + 16
    end
end

function MonsterZombie:hitbox(state, entity)
    local box = {}
    local anchor_x = -self.scalex
    
    if(state == State.Attack)
    then
        box = entity:boundingBoxRelative()
        box:scale(1.5, 1.0, anchor_x, RectAnchor.Bottom)
        box:translate(entity.pos.x, entity.pos.y)
    else
        box = Rect:new()
    end
    
    return box
end

function MonsterZombie:evHurt(entity, damages, owner)
    if(self.state ~= State.Hidden)
    then
        if(self.state == State.Dig or
        not self.fall_state:hurt(self, entity, damages))
        then
            local dmg = damages:clone()
            dmg.force = HitForce:new()
            return entity:hurtBase(dmg, owner)
        end
        return entity:hurtBase(damages, owner)
    end
    return Hit:new(HitType.NoContact)
end

function MonsterZombie:evGetHit(entity, owner, damages)
    entity:evGetHitBase(owner, damages)
    
    if(entity:alive()) then
        entity:soundPlay("hurt", entity.pos)
    end
    
    --TODO ajouter un particle emitter special pour le sang des monstres
    local box = entity:boundingBox()
    local pos = Vec2:new(box:center().x, box.y1)
    entity:getContext():particleSystem():burst(
        pcEntryIdFromString("pc_part_em_paint"), pos, Color:new(0,255,50))
end

function MonsterZombie:createVomit(entity, bullet_launch ,_scalex, status)
    if (bullet_launch == true) then
        return
    end
    
    
    local scalex = _scalex or 1
    
    local box = entity:boundingBox()
    local pos = Vec2:new(box:center().x + 9*scalex, box.y1 + 13)
    local angle = scalex < 0 and 160 or 20
    
    local spell = pcGenerateSpell(
        pcEntryIdFromString("zombie_spit"),
        entity:attribs().level,
        entity:targetType())
        
    if status:findEffect(StatusEffectType.Giant) then
        spell = pcGenerateSpell(
            pcEntryIdFromString("zombie_big_spit"),
            entity:attribs().level,
            entity:targetType())

    end
    pcCreateSpellSimple(
        entity:getContext(), spell, pos, angle,
        0) -- burst index, 0 = first
end

function MonsterZombie:evDie(entity, owner)
    entity:evDieBase(owner)
    self.frame = 0
    self.state = State.Die
    
    entity:soundPlay("die", entity.pos)
end

function MonsterZombie:makeBrain(entity)
    return BrainAI:new()
end

function MonsterZombie:haveRecoil(entity)
    if(self.state == State.Attack or self.state == State.Attack2)
    then
        return false
    end
    return self.state ~= State.TakeOut
end

function MonsterZombie:bbox()
    return self.rect
end

function MonsterZombie:facingx()
    return self.scalex
end

function MonsterZombie:isIdle()
    return self.state == State.Idle
end

function MonsterZombie:isMoving()
    return self.state == State.Move
end

function MonsterZombie:isJumping()
    return self.state == State.JumpAir
end

function MonsterZombie:isFalling()
    return self.state == State.Fall
end 

function MonsterZombie:canBeUsedAsMount(entity)
    return false
end

function MonsterZombie:drawLife(entity)
    if(self.state == State.Hidden or self.state == State.TakeOut) then
        return false
    else
        return entity:drawLife()
    end
end

function MonsterZombie:shouldInflictDamages(state, frame)
    return ((state == State.Attack and frame >= 4 and frame < 5) or
            (state == State.Attack2 and frame >= 7 and frame < 10))
end

-- Netplay (deprecated)

function MonsterZombie:evSend(entity, buf)
    Monster.evSend(self, entity, buf, 0x00)
end

function MonsterZombie:evReceive(entity, buf)
    Monster.evReceive(self, entity, buf)
end

-- Netplay

function MonsterZombie:evSendReliable(entity, buf)
    Monster.evSendReliable(Snapshot, self, entity, buf)
end

function MonsterZombie:evReceiveReliable(entity, buf)
    Monster.evReceiveReliable(Snapshot, entity, buf)
end

-- AI

function BrainAI:initialize()
    self.cooldown = 0.0
    self.dig_cooldown = 60.0 * 5
end

function BrainAI:update(m, entity, brain, inputs, dt)
    self.cooldown = self.cooldown - dt
    self.dig_cooldown = self.dig_cooldown - dt
    brain:updateAI(entity, inputs, dt)
    
    if(m.is_leader) then
        m.leader_effect:updateBrain(m, inputs, dt)
    elseif(m.state == State.Hidden)
    then
        inputs:simulateCheck(InputKey.MouseLeft)
    end
end

function BrainAI:tryToAttack(m, entity, focus, inputs)
    local dist = focus:distanceTo(entity:asAliveEntity())
    local facing = false
    local expert = 0
    
    local box1 = entity:boundingBox()
    local box2 = focus.box
    
    if(m:facingx() > 0.0)
    then
        facing = (box1.x2 <= box2.x1)
    else
        facing = (box1.x1 >= box2.x2)
    end
    
    local vsep = math.abs(box1:center().y - box2:center().y)
    local scale = m.size + 1
    
    
    if(facing and focus:canBeHit(m:hitbox(State.Attack, entity)))
    then
        inputs:simulateCheck(InputKey.MouseLeft)
        return true
        
    elseif(self.cooldown <= 0
        and facing)
    then
        inputs:simulateCheck(InputKey.MouseLeft)
        inputs:simulateCheck(InputKey.Down)
        self.cooldown = 600
        return true
        
    elseif(dist < 160 * scale
        and vsep < 32 * scale
        and math.random() < 0.001 * (1 + expert*10))
    then
        inputs:simulateCheck(InputKey.Space)
        inputs:simulateCheck(InputKey.Shift)
        
    elseif(m.dig_allowed and self.dig_cooldown <= 0 and dist > 300)
    then
        self.dig_cooldown = 60.0 * 10
        inputs:simulateCheck(InputKey.Action1)
    end
    
    return false
end


return MonsterZombie


