local bd = bd
local gamelog = require("common.gamelog")

local string_format = string.format

global.global.__AllClasses = global.global.__AllClasses or {}

local setmetatableindex_
setmetatableindex_ = function(t, index)
    local mt = getmetatable(t)
    if not mt then mt = {} end
    if not mt.__index then
        mt.__index = index
        mt.__call = index.__call
        mt.__tostring = index.__tostring
        setmetatable(t, mt)
    elseif mt.__index ~= index then
        setmetatableindex_(mt, index)
    end
end
setmetatableindex = setmetatableindex_

local lastDecorator = {}
function classDecorator(dec)
    assert(dec, "[error]decorator failed, dec or funcName is nil dec:", debug.traceback("[error]decorator failed, dec or funcName is nil dec:"))
    lastDecorator[#lastDecorator + 1] = dec
end

function DefineClass(classname, ...)
    local env = getfenv(2)
    if env[classname] == nil then
        env[classname] = {__cname = classname}
    else
        if not global.isReloading then
            -- reload的时候就不用提示了
            gamelog.error("Redefine class!!!", classname, debug.traceback())
        end
        setmetatable(env[classname], nil)
        env[classname].__cname = classname
    end

    local cls = env[classname]


    cls.class = cls

    -- 客户端保留原来的逻辑
    ---- 类重新执行DefineClass时(reload), 需要清理原有函数
    if global.component == "client" then
        if cls.__decoratedMethod then
            for funcName, _ in pairs(cls.__decoratedMethod) do
                cls[funcName] = nil
            end
        end
        cls.__decoratedMethod = {}
    else
    -- 服务端DefineClass保留装饰器函数
        cls.__decoratedMethod = cls.__decoratedMethod or {}
    end

    cls.__index = cls
    local function cls_new_index(t, k, v)
        local lastDecoratorCount = #lastDecorator
        if lastDecoratorCount > 0 and type(v) == 'function' then
            local final = v
            for i = lastDecoratorCount, 1, -1 do
                local last = final
                local cur = lastDecorator[i]
                --print("@@##classDecorator".."@"..classname.."@"..k)
                final = function(...) return cur(last, classname, k, ...) end
            end

            lastDecorator = {}
            cls.__decoratedMethod[k] = true
            rawset(t, k, final)
        else
            --热更时候试用于新加function装饰器
            cls.__decoratedMethod[k] = true
            rawset(t, k, v)
        end
    end

    cls.__supers = nil
    cls.__create = nil
    if select("#", ...) > 0 then
        local supers = {...}
        for _, super in ipairs(supers) do
            local superType = type(super)
            assert(superType == "nil" or superType == "table" or superType == "function",
            string_format("class() - create class \"%s\" with invalid super class type \"%s\"",
                classname, superType))

            if superType == "function" then
                assert(cls.__create == nil,
                string_format("class() - create class \"%s\" with more than one creating function",
                classname))
                -- if super is function, set it to __create
                cls.__create = super
            elseif superType == "table" then
                -- super is pure lua class
                cls.__supers = cls.__supers or {}
                cls.__supers[#cls.__supers + 1] = super
            else
                error(string_format("class() - create class \"%s\" with invalid super type",
                classname), 0)
            end
        end

        -- 如果父类中带有__create，就需要继承__create函数
        if cls.__create == nil and #cls.__supers == 1 and cls.__supers[1].__create then
            cls.__create = cls.__supers[1].__create
        end

        -- 如果有__create，就说明创建的是C++对象的
        if cls.__create then
            assert(#cls.__supers == 1, "must have 1 superclass")
            -- 需要用到特殊的继承方式
        else
            if not cls.__supers or #cls.__supers == 1 then
                setmetatable(cls, {__index = cls.__supers and cls.__supers[1], __newindex = cls_new_index})
            else
                local clsSupers = cls.__supers
                local function cls_index(_, key)
                    for i = 1, #clsSupers do
                        local super = clsSupers[i]
                        local v = super[key]
                        if v ~= nil then
                            return v
                        end
                    end

                    if #clsSupers > 0 then
                        -- 声明了需要将同Group的classType判定缓存，会在第一次访问is[ClassName]为nil时设置is[ClassName]=false，避免相关判定再次找不到的消耗
                        local classTypeGroupTable = rawget(cls, "cacheClassTypeDefineTable")
                        if classTypeGroupTable and classTypeGroupTable[key] then
                            cls[key] = false
                            return false
                        end
                    end
                end
                setmetatable(cls, {__index = cls_index, __newindex = cls_new_index})
            end
        end
    else
        setmetatable(cls, {__newindex = cls_new_index})
    end

    --用rawset 是因为前面为了装饰器 设置了原表
    rawset(cls,"new",function(...)
        local instance
        if cls.__create then
            instance = cls.__create(cls, ...)
        else
            instance = {}
            setmetatable(instance, cls)
        end

        if instance.ctor then
            instance:ctor(...)
        end
        return instance
    end)

    rawset(cls,"rawnew",function(...)
        local instance
        if cls.__create then
            instance = cls.__create(...)
        else
            instance = {}
            setmetatable(instance, cls)
        end
        return instance
    end)

    rawset(cls, "__tostring", cls.__tostring)

    global.global.__AllClasses[classname] = cls
    if global.postDefineClass then
        global.postDefineClass(classname, cls)
    end

    return cls
end