--[[
    safe链表-withpool
]]

---@class SafeLinkedList
-- 只允许从尾部插入，保证迭代安全

SafeLinkedList = {}
SafeLinkedList.__Listpool = {}
SafeLinkedList.__itemPool = {}

function SafeLinkedList.getListFromPool()
    local list = next(SafeLinkedList.__Listpool)
    if list then
        SafeLinkedList.__Listpool[list] = nil
        return list
    end

    list = {}
    list.head = {}
    list.tail = {}
    list.__removeList = {}
    SafeLinkedList.clear(list)
    return list
end

--清理池子
function SafeLinkedList.clearPool()
    SafeLinkedList.__Listpool = {}
    SafeLinkedList.__itemPool = {}
end


function SafeLinkedList.clear(list)
    list.head.__next = list.tail
    list.tail.__prev = list.head
    list.count = 0
end

function SafeLinkedList.getItemFromPool()
    local item = next(SafeLinkedList.__itemPool)
    if item then
        SafeLinkedList.__itemPool[item] = nil
        return item
    end
    item = {}
    return item
end

--回收列表
function SafeLinkedList.recycle(list)
    local item = list.head.__next
    while item ~= list.tail do
        local next = item.__next
        SafeLinkedList._recycleItem(item)
        item = next
    end

    --清理已移除的
    for _, node in pairs(list.__removeList) do
        SafeLinkedList._recycleItem(node)
    end
    SafeLinkedList.clear(list)
    table.clear(list.__removeList)
    SafeLinkedList.__Listpool[list] = true
end

--回收列表项
function SafeLinkedList._recycleItem(item)
    for k, _ in pairs(item) do
        item[k] = nil
    end
    item.__removed = false
  --  gamelog.error("SafeLinkedList._recycleItem", item)
    if not SafeLinkedList.__itemPool[item] then
        SafeLinkedList.__itemPool[item] = true
    end
end


function SafeLinkedList.create()
    return SafeLinkedList.getListFromPool()
end


-- pushBack返回节点后，自行设置数据，避免使用table
function SafeLinkedList.pushBack(list)
   -- gamelog.error("SafeLinkedList.pushBack", debug.traceback())
    local item = SafeLinkedList.getItemFromPool()
    item.__prev = list.tail.__prev
    item.__next = list.tail

    list.tail.__prev = item
    item.__prev.__next = item

    list.count = list.count + 1
    return item
end

function SafeLinkedList.remove(list, node)
    if node.__removed then
        error("Node is already removed")
    end
    node.__prev.__next = node.__next
    node.__next.__prev = node.__prev
    node.__removed = true
    list.__removeList[#list.__removeList + 1] = node

    list.count = list.count - 1
    return true
end

function SafeLinkedList.next(list, node)
    if node == nil then
        -- 从头开始遍历
        node = list.head
    end

    while node.__removed do
        node = node.__prev
    end

    if node.__next == list.tail then
        return nil
    else
        return node.__next
    end
end

function SafeLinkedList.last(list)
    if list.tail.__prev == list.head then
        return nil
    else
        return list.tail.__prev
    end
end
