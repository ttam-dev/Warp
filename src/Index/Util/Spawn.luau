--!strict
--!optimize 2

local MAX_POOL_SIZE = 50 -- Configurable pool size
local MIN_POOL_SIZE = 5  -- Minimum threads to keep alive

local threadPool: {thread} = {}
local poolSize = 0

local Assert = require(script.Parent.Assert)

-- Create worker function outside to avoid closure allocation
local function worker()
    while true do
        local func, args = coroutine.yield()
        if func then
            -- Use pcall for error safety
            local ok, err = pcall(func, table.unpack(args))
            if not ok then
               Assert(false, `Function execution failed: {err}`, 1)
            end
        end
    end
end

-- Pre-populate pool with minimum threads
local function initializePool()
    for _ = 1, MIN_POOL_SIZE do
        local co = coroutine.create(worker)
        coroutine.resume(co) -- Initialize the coroutine
        table.insert(threadPool, co)
        poolSize = poolSize + 1
    end
end

-- Get or create a thread from the pool
local function getThread(): thread
    if poolSize > 0 then
        poolSize = poolSize - 1
        return table.remove(threadPool) :: thread
    else
        local co = coroutine.create(worker)
        coroutine.resume(co) -- Initialize the coroutine
        return co
    end
end

-- Return thread to pool
local function returnThread(co: thread)
    if poolSize < MAX_POOL_SIZE and coroutine.status(co) == "suspended" then
        poolSize = poolSize + 1
        table.insert(threadPool, co)
    end
    -- If pool is full or thread is dead, let it be garbage collected
end

-- Initialize pool on first require
initializePool()

-- Main spawn function
return function<T...>(func: (T...) -> (), ...: T...)
    -- Pack arguments immediately to avoid holding references
    local args = table.pack(...)
    
    local co = getThread()
    
    -- Schedule the execution
    task.spawn(function()
        coroutine.resume(co, func, args)
        returnThread(co)
    end)
end