-- Lua的table池
-- 注意：一个没有fetch过的tag即使调用release接口也不会被缓存！

local gamelog = jn_require_ex("common.gamelog")

local tblNew = table.new
local tblClear = table.clear

---@class TablePool
local TablePool = DefineClass("TablePool")

-- 每个Pool允许缓存的table的最大数量
function TablePool:ctor(maxPoolSize)
    self.maxPoolSize = maxPoolSize
    self.pools = tblNew(0, 8)
end

-- 从Pool中获取一个tag对应的table，如果不存在则初始化narr个数组域和nhash个哈希域
function TablePool:fetch(tag, narr, nhash)
    local pool = self.pools[tag]
    if pool then
        local len = pool.count
        if len > 0 then
            local tbl = pool[len]
            pool[len] = nil
            pool.count = len - 1
            return tbl
        end
    else
        pool = tblNew(4, 1)
        pool.count = 0
        self.pools[tag] = pool
    end
    return tblNew(narr, nhash)
end

-- 释放一个table到tag对应的pool中，如果noclear为true则不释放其中的空间
-- 注意:noclear为true意味着引用的内容不会被GC回收!
function TablePool:release(tag, tbl, noclear)
    if not tbl then
        return
    end
    local pool = self.pools[tag]

    -- 没有fetch过的对象不进行缓存！
    if not pool then
        return
    end

    if not noclear then
        tblClear(tbl)
    end

    local len = pool.count + 1
    if len <= self.maxPoolSize then
        pool[len] = tbl
        pool.count = len
    end
end

-- 销毁table池
function TablePool:destroy()
    self.pools = nil
end

function TablePool:dumpCountInfo()
    gamelog.info("============= TablePool:dumpInfo start ===============")
    for k, v in pairs(self.pools) do
        gamelog.info(k, ":", v.count)
    end
    gamelog.info("============= TablePool:dumpInfo end ===============")
end