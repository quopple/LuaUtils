-- 用于存储持续更新的逻辑事件的类，执行顺序按照添加顺序进行
-- 处理了文件执行错误以及执行时添加删除事件的情况
-- 一个持续的逻辑如果出现了traceback，会被移除以防止持续的报错
local sampleProfiler = require("common.utils.profiler_utils")
local list = require("list")
local ilist = ilist
local type = type
local safecall = bd.safecall

local UpdateEvent = DefineClass("UpdateEvent")
local tblInsert = table.insert
local beginSample = sampleProfiler.beginSample
local endSample = sampleProfiler.endSample

local OP_FLAG_ADD = 1
local OP_FLAG_REMOVE = 2

function UpdateEvent:ctor(name)
    self.name = name
    self.events = list:new()
    self.opList = {}           --在执行update过程中被添加或者删除的列表，{{func, OP_FLAG_ADD/OP_FLAG_REMOVE}}
    self.isUpdating = false
    self.frameCount = 0
end

function UpdateEvent:destroy()
    self.events:clear()
    self.opList = {}
    self.isUpdating = false
end

--[[
    @desc: 添加一个事件
    author:{dongxi}
    time:2020-02-16 23:45:37
    --@func: 事件的回调函数，无参数，如需参数自己进行封装
    --@importent: 为true表示重要事件，运行出错之后依然继续保留
    @return: 事件的Handler，用于removeEvent使用
]]

-- 注：removed 和 toBeRemoved 的区别：前者用于list内部（详见list.lua），后者用于本代码handle的移除标记
function UpdateEvent:addEvent(func, importent, desc)
    if func then
        if not desc then
            gamelog.error("please add desc for profiler", debug.traceback())
        end
        local handle = {value = func, _prev = 0, _next = 0, removed = true, _keep = importent, desc = desc, toBeRemoved = false}
        if self.isUpdating then
            tblInsert(self.opList, {handle, OP_FLAG_ADD})
        else
            self.events:pushnode(handle)
        end
        return handle
    end
    return nil
end

--[[
    @desc: 删除事件
    author:{author}
    time:2020-02-16 23:46:38
    --@handle: 添加事件时获取到的handle对象，注意请勿使用原本的函数对象，防止同一个函数对象被多次加入移除时产生问题。
    @return: 无
]]
function UpdateEvent:removeEvent(handle)
    if handle then
        if handle._prev == nil or handle._next == nil then
            gamelog.error("The handler is removed already, please check if there is an error when update function executing!", handle.desc, debug.traceback())
            return
        end
        if type(handle) ~= "table" then
            gamelog.error("You should use the return value of addEvent to remove it, not function itself!", handle.desc, debug.traceback())
            return
        end
        handle.toBeRemoved = true
        if self.isUpdating then
            tblInsert(self.opList, {handle, OP_FLAG_REMOVE})
        else
            self.events:remove(handle)
        end
    end
end

function UpdateEvent:update()
    local _list = self.events
    self.isUpdating = true
    self.frameCount = self.frameCount + 1
    beginSample(self.name)
    for node, f in ilist(_list) do
        if not node.toBeRemoved then
            local flag = false
            if node.desc then
                beginSample(node.desc)
                flag = safecall(f)
                endSample()
            else
                flag = safecall(f)
            end

            if not flag then
                if node._keep ~= true then
                    node.toBeRemoved = true
                    tblInsert(self.opList, {node, OP_FLAG_REMOVE})
                end
            end
        end
    end
    endSample()
    local opList = self.opList
    self.isUpdating = false

    for i, op in ipairs(opList) do
        local handle = op[1]
        local opFlag = op[2]
        if opFlag == OP_FLAG_ADD then
            self.events:pushnode(handle)
        elseif opFlag == OP_FLAG_REMOVE then
            self.events:remove(handle)
        end
        opList[i] = nil
    end
end

function UpdateEvent:count()
    return self.events.length
end

function UpdateEvent:dump()
    local count = 0
    gamelog.info("Update event name: ", self.name)
    for _, v in ilist(self.events) do
        gamelog.info("update function: ", v)
        count = count + 1
    end

    gamelog.info("all function is:", count)
end