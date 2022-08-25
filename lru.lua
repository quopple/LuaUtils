
local logUtils = jn_require_ex("common.utils.log_utils")

LRU = DefineClass("LRU")
LRU.logPrefix = "LRU"
logUtils.addInstanceLogFunc(LRU)
---- private method ----
function LRU:ctor(capacity, eliminatedCb)
    capacity = math.floor(capacity)
    if capacity < 1 or type(eliminatedCb) ~= "function" then
        error("LRU:ctor(capacity, eliminatedCb)")
    end

    self._capacity = capacity
    self._size = 0
    self._eliminatedCb = eliminatedCb
    -- list
    self._head = {_prev=nil, _next=nil, _key=nil}
    self._tail = {_prev=self._head, _next=nil, _key=nil}
    self._head._next = self._tail
    -- map
    self._map = {}
end

function LRU:_dump()
    self:logDebug("====LRU:_dump()====", self._capacity, self._size)
    local node = self._head._next
    while node ~= self._tail do
        self:logDebug(node._key)
        node = node._next
    end
end

function LRU:_callback(key)
    local res, err = pcall(self._eliminatedCb, key)
    if not res then
        self:logError(err)
    end
end

---- public method ----
function LRU:update(key)
    local node = self._map[key]
    if node then
        -- link node.prev <--> node.next
        node._prev._next = node._next
        node._next._prev = node._prev
        -- link head <--> node <--> head.next
        node._next = self._head._next
        node._next._prev = node
        self._head._next = node
        node._prev = self._head
    else
        node = {_prev = self._head, _next = self._head._next, _key = key}
        self._head._next = node
        node._next._prev = node
        self._map[key] = node
        if self._size == self._capacity then
            local elimNode = self._tail._prev
            elimNode._prev._next = self._tail
            self._tail._prev = elimNode._prev
            self._map[elimNode._key] = nil
            self:_callback(elimNode._key)
        else
            self._size = self._size + 1
        end
    end
end

function LRU:remove(key)
    local node = self._map[key]
    if node then
        node._prev._next = node._next
        node._next._prev = node._prev
        self._map[key] = nil
        self._size = self._size - 1
    end
end

function LRU:resize(capacity)
    capacity = math.floor(capacity)
    if capacity < 1 then
        error("LRU:resize(capacity)")
    end
    self._capacity = capacity
    if self._size > capacity then
        local cnt = self._size - capacity
        self._size = capacity
        -- batch eliminate
        local lastNode = self._tail._prev
        local keyset = {}
        while cnt > 0 do
            cnt = cnt - 1
            self._map[lastNode._key] = nil
            table.insert(keyset, lastNode._key)
            lastNode = lastNode._prev
        end
        lastNode._next = self._tail
        self._tail._prev = lastNode
        -- batch callback
        for _, key in ipairs(keyset) do
            self:_callback(key)
        end
    end
end


--[[ test
local function onEliminated(key)
    print("onEliminated", key)
end
local capacity = 3
local from, to = 1, 5

local l = LRU.new(capacity, onEliminated)
-- print(collectgarbage("collect"))
-- print(collectgarbage("count"))
-- for j=1, 300000 do
for j=1, 3 do
    for i=from, to do
        l:update(i)
    end
    l:_dump()
    for i=to, from, -1 do
        l:update(i)
    end
    l:_dump()
end
-- print(collectgarbage("collect"))
-- print(collectgarbage("count"))
-- l:_dump()
print("-----------------")
l:remove(2)
l:remove(5)
l:_dump()
for i=from, to do
    l:remove(i)
end
l:_dump()
for i=from, to do
    l:update(i)
end
l:resize(10)
l:_dump()
l:resize(1)
l:_dump()
--]]