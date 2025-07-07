--!strict
--!optimize 2
--!native
local myTablesUtils = {}

local Assert = require(script.Parent.Assert)

--\\ Local Function

-- Recursively clears all entries in a table
-- This is used to ensure that all nested tables are cleared before removing the entry
local function deepClean(tbl: {})
	for k, v in pairs(tbl) do
		if typeof(v) == "table" then
			deepClean(v)
		end
		tbl[k] = nil
	end
end

--\\ Public Functions

-- Clears a table entry by identifier (if it's a table), then removes it
function myTablesUtils.clearEntry(map: {}, identifier: any)
	Assert(typeof(map) == "table", "Expected a table for map")
	local entry = map[identifier]
	if typeof(entry) == "table" then
		deepClean(entry)
	end
	map[identifier] = nil
end

return myTablesUtils
