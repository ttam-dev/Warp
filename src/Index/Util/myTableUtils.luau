--!strict
--!optimize 2

local myTableUtils = {}

local Assert = require(script.Parent.Assert)

function myTableUtils.ensure(tbl: any, key: any)
    Assert(typeof(tbl) == "table", "Expected a table to ensure.", 2)
    if tbl[key] == nil then
        tbl[key] = {}
    end
end

function myTableUtils.recycle(tbl: {})
    Assert(typeof(tbl) == "table", "Expected a table to recycle.", 2)
    table.clear(tbl)
end

function myTableUtils.clear(map: {}, key: any)
    Assert(typeof(map) == "table", "Expected a table (map) to clear from.", 2)
    local t = map[key]
    if typeof(t) == "table" then
        table.clear(t)
    end
    map[key] = nil
end

return myTableUtils