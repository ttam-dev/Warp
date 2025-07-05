--!strict
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
	Assert(IsServer, `Calling .Server({Identifier}) on client side (expected server side)`, 2)
	Assert(typeof(Identifier) == "string", `Identifier must be a string type, got {typeof(Identifier)}`, 2)
	return require(Server.Index)(Identifier, conf) :: Type.Server
end

function Index.Client(Identifier: string, conf: Type.ClientConf?): Type.Client
	Assert(not IsServer, `Calling .Client({Identifier}) on server side (expected client side)`, 2)
	Assert(typeof(Identifier) == "string", `Identifier must be a string type, got {typeof(Identifier)}`, 2)
	return require(Client.Index)(Identifier, conf) :: Type.Client
end

function Index.fromServerArray(arrays: { string } | { [string]: Type.ServerConf }): Type.fromServerArray
	Assert(IsServer, `Calling .fromServerArray({arrays}) on client side (expected server side)`, 2)
	Assert(typeof(arrays) == "table", "Array must be a table type, got {typeof(arrays)}", 2)
	local copy: { [string]: Type.Server } = {}
	for param1: string | number, param2: string | Type.ServerConf in pairs(arrays) do
		if typeof(param2) == "table" and typeof(param1) == "string" then
			copy[param1] = Index.Server(param1, param2)
		else
			if typeof(param2) == "string" then
				copy[param2] = Index.Server(param2)
			end
		end
	end
	return copy
end

function Index.fromClientArray(arrays: { string } | { [string]: Type.ClientConf }): Type.fromClientArray
	Assert(not IsServer, `Calling .fromClientArray({arrays}) on server side (expected client side)`, 2)
	Assert(typeof(arrays) == "table", `Array must be a table type, got {typeof(arrays)}`, 2)
	local copy = {}
	for param1: string | number, param2: string | Type.ClientConf in pairs(arrays) do
		if typeof(param2) == "table" and typeof(param1) == "string" then
			copy[param1] = Index.Client(param1, param2)
		else
			if typeof(param2) == "string" then
				copy[param2] = Index.Client(param2)
			end
		end
	end
	return copy
end

function Index.Signal(Identifier: string)
	return Signal(Identifier)
end

function Index.fromSignalArray(arrays: { any })
	Assert(typeof(arrays) == "table", `Array must be a table type, got {typeof(arrays)}`, 2)
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