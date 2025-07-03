--!strict
--!native
--!optimize 2
local Index = {}

local RunService = game:GetService("RunService")
local IsServer = RunService:IsServer()

local Util = script.Util
local Server = script.Server
local Client = script.Client

local Type = require(script.Type)
local Assert = require(Util.Assert)
local Signal = require(script.Signal)
local Buffer = require(Util.Buffer)

local onSpamSignal = Signal("Warp_OnSpamSignal")

if IsServer then
	require(Server.ServerProcess).start()
else
	require(Client.ClientProcess).start()
end

Index.OnSpamSignal = onSpamSignal

function Index.Server(Identifier: string, conf: Type.ServerConf?): Type.Server
	Assert(IsServer, `[Warp]: Calling .Server({Identifier}) on client side (expected server side)`)
	Assert(typeof(Identifier) == "string", `[Warp]: Identifier must be a string type, got {typeof(Identifier)}`)
	return require(Server.Index)(Identifier, conf) :: Type.Server
end
function Index.Client(Identifier: string, conf: Type.ClientConf?): Type.Client
	Assert(not IsServer, `[Warp]: Calling .Client({Identifier}) on server side (expected client side)`)
	Assert(typeof(Identifier) == "string", `[Warp]: Identifier must be a string type, got {typeof(Identifier)}`)
	return require(Client.Index)(Identifier, conf) :: Type.Client
end

function Index.fromServerArray(arrays: { string } | { [string]: Type.ServerConf }): Type.fromServerArray
	Assert(IsServer, `[Warp]: Calling .fromServerArray({arrays}) on client side (expected server side)`)
	Assert(typeof(arrays) == "table", "[Warp]: Array must be a table type, got {typeof(arrays)}")

	local copy: { [string]: Type.Server } = {}

	-- Use raw type narrowing via # operator to assume it's an array
	if #arrays > 0 then
		-- Narrow the type to {string}
		local stringArray = arrays :: { string }
		for _, param: string in ipairs(stringArray) do
			copy[param] = Index.Server(param)
		end
	else
		-- Narrow the type to {[string]: Type.ServerConf}
		local dictArray = arrays :: { [string]: Type.ServerConf }
		for key, conf in pairs(dictArray) do
			copy[key] = Index.Server(key, conf)
		end
	end

	return copy
end

function Index.fromClientArray(arrays: { string } | { [string]: Type.ClientConf }): Type.fromClientArray
	Assert(not IsServer, `[Warp]: Calling .fromClientArray({arrays}) on server side (expected client side)`)
	Assert(typeof(arrays) == "table", `[Warp]: Array must be a table type, got {typeof(arrays)}`)

	local copy: { [string]: Type.Client } = {}

	if #arrays > 0 then
		-- It's an array of strings
		local stringArray = arrays :: { string }
		for _, param in ipairs(stringArray) do
			copy[param] = Index.Client(param)
		end
	else
		-- It's a dictionary of ClientConf
		local confDict = arrays :: { [string]: Type.ClientConf }
		for key, conf in pairs(confDict) do
			copy[key] = Index.Client(key, conf)
		end
	end

	return copy
end

function Index.Signal(Identifier: string)
	return Signal(Identifier)
end

function Index.fromSignalArray(arrays: { any })
	Assert(typeof(arrays) == "table", `[Warp]: Array must be a table type, got {typeof(arrays)}`)
	local copy = {}
	for _, identifier: string in arrays do
		copy[identifier] = Index.Signal(identifier)
	end
	return copy :: typeof(copy)
end

function Index.buffer()
	return Buffer.new()
end

return table.freeze(Index) :: typeof(Index)
