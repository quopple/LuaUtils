local gamelog = require_ex("common.gamelog")
local mathUtils = require_ex("common.utils.math_utils")
local combatEventDefine = require_ex("common.combat.const.combat_event_define")
local frameworkEventDefine = require_ex("framework.event.framework_event_define")
local SafeLinkedList = require_ex("common.utils.linked_list").SafeLinkedList
local Vector3 = Vector3
local sin, cos, rad = math.sin, math.cos, math.rad
local getTableWithDefaultValue = table.getTableWithDefaultValue


---@class CombatEntity 战斗实体基类。
local CombatEntity = DefineClass("CombatEntity", Entity)

function table.getTableWithDefaultValue(createFunc)
    return setmetatable({}, {__index=function(self, name)
        if name == "__cname" then
            return nil
        end
        local value = createFunc()
        self[name] = value
        return value
    end})
end


function CombatEntity:ctor()
    self.addedComponents = {}
    self.forwardDir = Vector3.new(0, 0, 0)
    self.logPrefix = string.format("[%s:%s:%d]", self.__cname, self.id, self.objectId)
    self:logInfo("CombatEntity:ctor", self.__cname)
    self.registeredEvent = getTableWithDefaultValue(SafeLinkedList.create)
    self.entity = self -- 事件系统用

    -- 在单位身上保存一下world，与服务端的entity.world对应的
    -- ---@type ClientBattleWorld
    -- self.world = global.game.battleWorld
    -- -- world来持有一下
    -- self.world:addEntityToWorld(self)
end

function CombatEntity:onEntityPrepared()
    local x, y, z, yaw = self.position[1], self.position[2], self.position[3], self.yaw
    self:logInfo("CombatEntity:onEntityPrepared", x, y, z, yaw)
    self:safeCallAllComponents("postInit")
end

-- 初始化客户端独有的组件，子类覆盖来添加组件
-- 此方法调用时，场景已经加载
function CombatEntity:_addInitComponents()
end

function CombatEntity:onSceneLoaded()
    self:logDebug("CombatEntity:onSceneLoaded")
    self:_addInitComponents()
    self:createActor()
    self:emitEvent(combatEventDefine.UNIT_ENTER_SCENE)
end

function CombatEntity:createActor()
    -- 创建对应的actor，这里的特殊一点点
    ---@type Actor
    self.actor = global.game.actorMgr:createActor(self)
    -- global.eventManager:executeLuaEvent(frameworkEventDefine.ON_COMBAT_ACTOR_ENTER_WORLD, self.objectId)
end

function CombatEntity:getCombatType()
    return self.combatType
end

function CombatEntity:leaveWorld()
    gamelog.info("CombatEntity:leaveWorld", self.position[1], self.position[2], self.position[3])
    -- if self.actor then
    --     global.eventManager:executeLuaEvent(frameworkEventDefine.ON_COMBAT_ACTOR_LEAVE_WORLD, self.objectId, self.actor:getRootViewId())
    -- end
    -- global.game.actorMgr:destroyActor(self.objectId)
    -- self.actor = nil
    -- self.world:removeEntityFromWorld(self)
    self:_removeInitClientComponents()
    -- -- 清理components
    self:safeCallAllComponents("destroy")
    self:safeCallAllComponents("finalize")
    -- 移除事件注册
    self.registeredEvent = {}
end

--[[
    [DEBUG]换英雄step1
    def: CombatEntity
    @rpc
]]
function CombatEntity:preSwitchConfId()
    if self.actor then
        global.eventManager:executeLuaEvent(frameworkEventDefine.ON_COMBAT_ACTOR_LEAVE_WORLD, self.objectId,self.actor:getRootViewId())
        global.game.actorMgr:destroyActor(self.objectId)
        self.actor = nil
    end
    self:_removeInitClientComponents()
    self:safeCallAllComponents("destroy")
    self:safeCallAllComponents("finalize")
end

--[[
    [DEBUG]换英雄step2
    def: CombatEntity
    @rpc
]]
function CombatEntity:switchConfIdDone()
    self:safeCallAllComponents("postInit")
    self:_addInitComponents()
    self:createActor()
end

function CombatEntity:_removeInitClientComponents()
end

--[[
    服务端删除Component
    def: CombatEntity
    @rpc
    string componentName
]]
function CombatEntity:serverRemoveComponent(componentName)
    local comp = self[componentName]
    if comp then
        comp:destroy()
        comp:finalize()
    end
end

function CombatEntity:update_diff_position(modifies, delKeys)
    if self.colliderComp then
        self.colliderComp:updatePositionAndRotation()
    end
end

function CombatEntity:getPosition()
    return self.position[1], self.position[2], self.position[3]
end

function CombatEntity:getYaw()
    return self.yaw
end

function CombatEntity:getDir()
    self.forwardDir:set(sin(rad(self.yaw)), 0, cos(rad(self.yaw)))
    return self.forwardDir
end


function CombatEntity:emitPRChanged(x, y, z, yaw, immediately)
    if not x then
        x, y, z = self:getPosition()
    end
    if not yaw then
        yaw = self:getYaw()
    end
    self:executeLuaEvent(frameworkEventDefine.ON_ENTITY_POSITION_CHANGED, x, y, z, immediately)
    self:executeLuaEvent(frameworkEventDefine.ON_ENTITY_ROTATION_CHANGED, yaw, immediately)
end

function CombatEntity:isPlayer()
    return false
end

function CombatEntity:getId()
    return self.objectId
end

function CombatEntity:onRouteSyncTick(moving, turning, position, pitch, yaw, roll, speed, turnDirection, curTime, isInterpolation, moveStatus)
    if not self.isMoving and moving then
        self.isMoving = true
    elseif self.isMoving and not moving then
        self.isMoving = false
    end

    yaw = mathUtils.normalizeAxis(yaw)
    if self.moveComp then
        self.moveComp:updatePosAndYawFromServer(position[1], position[2], position[3], yaw, speed, moving, isInterpolation, moveStatus)
    end

    self:emitPRChanged(position[1], position[2], position[3], yaw)
end

function CombatEntity:addCombatTimer(timeout, interval, func, maxRepeat)
    if interval == 0 then
        return self:addTimer(timeout, 0, func)
    else
        return self:addTimer(timeout, interval, func, maxRepeat or 0)
    end
end

function CombatEntity:cancelCombatTimer(timerId)
    self:cancelTimer(timerId)
end


function CombatEntity:logDebug(...)
    gamelog.debug(self.logPrefix, ...)
end

function CombatEntity:logInfo(...)
    gamelog.info(self.logPrefix, ...)
end

function CombatEntity:logError(...)
    gamelog.error(self.logPrefix, ...)
end

function CombatEntity:logWarn(...)
    gamelog.warn(self.logPrefix, ...)
end

function CombatEntity:logImportant(...)
    gamelog.error(self.logPrefix, ...)
end

function CombatEntity:onRouteStartFalling(speed, gravity)
    if self.moveComp then
        self.moveComp:onRouteSyncStartFall(gravity, speed[2])
    end
end

----------以下是事件注册和分发机制----------
function CombatEntity:addEventHandler(eventId, functionName)
    self:_addEventHandler(eventId, "entity", functionName)
end

function CombatEntity:removeEventHandler(eventId, functionName)
    self:_removeEventHandler(eventId, "entity", functionName)
end

function CombatEntity:registerEventListener(eventId, target, functionName)
    if self:unregisterEventListener(eventId, target) then
        self:logError("Duplicate register event handler, overriding existing", eventId, target, functionName)
    end

    local handlersOfEventId = self.registeredEvent[eventId]
    local node = SafeLinkedList.pushBack(handlersOfEventId)
    node.target = target
    node.functionName = functionName
end

function CombatEntity:unregisterEventListener(eventId, target)
    local list = self.registeredEvent[eventId]
    local iter = SafeLinkedList.next(list)
    while iter ~= nil do
        if iter.target == target then
            SafeLinkedList.remove(list, iter)
            return true
        end
        iter = SafeLinkedList.next(list, iter)
    end
    return false
end

function CombatEntity:_addEventHandler(eventId, componentName, functionName)
    -- 先看看原来是否有此监听
    if self:_removeEventHandler(eventId, componentName, functionName) then
        -- 报错待修，但不引起逻辑错误
        self:logError("Duplicate add event handler", eventId, componentName, functionName)
    end
    local handlersOfEventId = self.registeredEvent[eventId]
    local node = SafeLinkedList.pushBack(handlersOfEventId)
    node.componentName = componentName
    node.functionName = functionName
end

function CombatEntity:_removeEventHandler(eventId, componentName, functionName)
    local list = self.registeredEvent[eventId]
    local iter = SafeLinkedList.next(list)
    while iter ~= nil do
        if iter.componentName == componentName and iter.functionName == functionName then
            SafeLinkedList.remove(list, iter)
            return true
        end
        iter = SafeLinkedList.next(list, iter)
    end
    return false
end



function CombatEntity:emitEvent(eventId, ...)
    -- 死循环emit靠超时保护，不做callLayer保护了
    if self.registeredEvent:hasItem(eventId) then
        local list = self.registeredEvent[eventId]
        local iter = SafeLinkedList.next(list)
        while iter ~= nil do
            local callbackTarget
            if iter.target then
                callbackTarget = iter.target
            else
                callbackTarget = self[iter.componentName]
            end

            if callbackTarget then
                callbackTarget[iter.functionName](callbackTarget, ...)
            else
                self:logError("Component", iter.componentName, "forget to remove event handler", iter.functionName, "for event", eventId)
                self:addCombatTimer(1, 0, function() self:removeEventHandler(eventId, iter.componentName, iter.functionName) end)
            end
            iter = SafeLinkedList.next(list, iter)
        end
    end
end

CombatEntity.executeLuaEvent = CombatEntity.emitEvent

----------以上是事件注册和分发机制----------

function CombatEntity:callAllComponents(method, ...)
    for _, component in pairs(self.addedComponents) do
        local func = component[method]
        if func then
            func(component, ...)
        end
    end
end

function CombatEntity:safeCallAllComponents(method, ...)
    for _, component in pairs(self.addedComponents) do
        local func = component[method]
        if func then
            local success, result = xpcall(func, component, ...)
            if not success then
                self:logError("call component failed", method, result)
            end
        end
    end
end
