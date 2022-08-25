require "debug"

---
--- Inner functions
---
-------------------------------------------------------------------------------------------

---
--- Inner functions for pythonic decorator which is recommended for global functions.
---
local switchGlobalDecorators = {}
local globalDecorators = {}

local function setCurEnvDec()
    local old_env = getfenv(3)
    local old_mt = getmetatable(old_env) or {}
    local old_newindex = old_mt.__newindex
    local old_index = old_mt.__index
    local mt = {
        __newindex = function (t, k, v)
            if #globalDecorators > 0 and next(globalDecorators) and type(v) == "function" then
                for i = #globalDecorators, 1, -1 do
                    v = globalDecorators[i](v)
                end
                globalDecorators = {}
            end
            if old_newindex then
                if type(old_newindex) == "table" then
                    old_newindex[k] = v
                elseif type(old_newindex) == "function" then
                    old_newindex(t, k, v)
                end
            else
                rawset(t, k, v)
            end
        end,

        __index = old_index
    }
    setmetatable(old_env, mt)
end

---
--- Inner functions for pythonic decorator which is recommended for CLASS METHODS.
---
local methodDecorators = {}
local dClassIndex = {}
local dClassMT = {
    __newindex = function (t, k, v)
        if #methodDecorators > 0 and next(methodDecorators) and type(v) == "function" then
            for i = #methodDecorators, 1, -1 do
                v = methodDecorators[i](v)
            end
            methodDecorators = {}
        end
        t[dClassIndex][k] = v
    end,

    __index = function(t, k)
        return t[dClassIndex][k]
    end,
}

---
--- API
---
-------------------------------------------------------------------------------------------

---@param dec function
---@param fun function
---@return function
function DECORATOR_COMMON(dec, fun)
    return function(...)
        dec(fun, ...)
    end
end

---@param dec function
---@return nil
function DECORATOR_GLOBAL(dec)
    local old_env = getfenv(2)
    if not switchGlobalDecorators[old_env] then
        setCurEnvDec()
        switchGlobalDecorators[old_env] = true
    end
    globalDecorators[#globalDecorators + 1] = dec
end

--- Wrap class
---@param class table
---@return table
function DECORATOR_PROXY_CLASS(class)
    if getmetatable(class) == dClassMT then
        return class
    end
    local proxy = {}
    proxy[dClassIndex] = class
    setmetatable(proxy, dClassMT)
    return proxy
end

--- Wrap method
---@param dec function
---@return nil
function DECORATOR_METHOD(dec)
    methodDecorators[#methodDecorators + 1] = dec
end

---@param handler function
---@return nil
function DEFER(handler)
    local h, m, c = debug.gethook()
    local fun = debug.getinfo(2, "f").func
    local function hook(mode)
        local caller = debug.getinfo(2, "f").func
        if (mode == "call" and caller == error or caller == assert) or
                (mode == "return" and caller == fun) then
            handler()
            debug.sethook(h, m, c)
        end
    end
    debug.sethook(hook, "cr")
end

---
---@param context function(coroutine in fact)
---@return function
function WITH(context, ...)
    co = coroutine.wrap(context)
    res = co(...)
    return function(fun)
        pcall(fun, res)
        co()
    end
end

---@param fun function(coroutine in fact)
---@return function
function ITERATOR(fun, ...)
    local co = coroutine.wrap(fun)
    local args = {...}
    return function()
        return co(unpack(args))
    end
end

---
--- You can call this function in the beginning of lua project if you want to
--- FORBID UNDEFINED VARIABLE. It will raise error when undefined variable is used.
---
function setCurEnvForbidUndefined()
    local old_env = getfenv(1)
    local old_mt = getmetatable(old_env) or {}
    local old_index = old_mt.__index
    local old_newindex = old_mt.__newindex or rawset
    local common_mt_handle = setmetatable({}, {__index=function(_, _) error("Undefned varaible") end})
    local mt = {
        __index = function (t, k)
            local v
            if type(old_index) == "table" then
                v = old_index[k]
            elseif type(old_index) == "function" then
                v = old_index(t, k)
            elseif old_index ~= nil then
                error("Invalid __index")
            end
            if v == nil then
                error("Undefned varaible")
            end
            return v
        end,
        -- 此处对于普通class不处理，因为一方面可能会被外部重设metatable，另一方面普通和数据table太多。故普通class需要的时候自行处理
        -- 目前只处理defineClass中有supers的情况
        __newindex = function(t, k, v)
            if type(v) ~= "table" or v["__supers"] == nil then
                old_newindex(t, k, v)
                return
            end
            local supers = v["__supers"]
            supers[#supers + 1] = common_mt_handle
        end
    }
    setmetatable(old_env, mt)
end
