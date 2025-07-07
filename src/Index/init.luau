--[[
	Index

	This module provides the main API surface for the Warp system, handling both server and client initialization,
	signal management, and utility functions for creating and managing server/client instances and signals.

	Module Members:
	- OnSpamSignal: Signal instance for "Warp_OnSpamSignal" events.

	Functions:
	- Server(Identifier: string, conf: Type.ServerConf?): Type.Server
		Initializes and returns a server instance for the given Identifier and optional configuration.
		Throws if called on the client side or if Identifier is not a string.

	- Client(Identifier: string, conf: Type.ClientConf?): Type.Client
		Initializes and returns a client instance for the given Identifier and optional configuration.
		Throws if called on the server side or if Identifier is not a string.

	- fromServerArray(arrays: { string } | { [string]: Type.ServerConf }): Type.fromServerArray
		Creates a table of server instances from an array or dictionary of identifiers/configurations.
		Throws if called on the client side or if arrays is not a table.

	- fromClientArray(arrays: { string } | { [string]: Type.ClientConf }): Type.fromClientArray
		Creates a table of client instances from an array or dictionary of identifiers/configurations.
		Throws if called on the server side or if arrays is not a table.

	- Signal(Identifier: string)
		Creates and returns a new Signal instance for the given Identifier.

	- fromSignalArray(arrays: { any })
		Creates a table of Signal instances from an array of identifiers.

	- buffer()
		Creates and returns a new Buffer instance.

	Notes:
	- The module auto-initializes server or client processes based on the current execution context.
	- All returned tables and the module itself are frozen to prevent modification.
]]
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

if IsServer then
	require(Server.ServerProcess).start()
else
	require(Client.ClientProcess).start()
end

Index.OnSpamSignal = Signal("Warp_OnSpamSignal")

function Index.Server(Identifier: string, conf: Type.ServerConf?): Type.Server
	Assert(IsServer, `Calling .Server({Identifier}) on client side (expected server side)`)
	Assert(typeof(Identifier) == "string", `Identifier must be a string type, got {typeof(Identifier)}`)
	return require(Server.Index)(Identifier, conf) :: Type.Server
end
function Index.Client(Identifier: string, conf: Type.ClientConf?): Type.Client
	Assert(not IsServer, `Calling .Client({Identifier}) on server side (expected client side)`)
	Assert(typeof(Identifier) == "string", `Identifier must be a string type, got {typeof(Identifier)}`)
	return require(Client.Index)(Identifier, conf) :: Type.Client
end

function Index.fromServerArray(arrays: { string } | { [string]: Type.ServerConf }): Type.fromServerArray
	Assert(IsServer, `Calling .fromServerArray({arrays}) on client side (expected server side)`)
	Assert(typeof(arrays) == "table", "Array must be a table type, got {typeof(arrays)}")
	local copy: { [string]: Type.Server } = {}
	for param1, param2: string | Type.ServerConf in pairs(arrays) do
		if typeof(param2) == "table" then
			copy[param1] = Index.Server(param1, param2)
		else
			copy[param2] = Index.Server(param2)
		end
	end
	return copy
end

function Index.fromClientArray(arrays: { string } | { [string]: Type.ClientConf }): Type.fromClientArray
	Assert(not IsServer, `Calling .fromClientArray({arrays}) on server side (expected client side)`)
	Assert(typeof(arrays) == "table", `Array must be a table type, got {typeof(arrays)}`)
	local copy = {}
	for param1, param2: string | Type.ClientConf in pairs(arrays) do
		if typeof(param2) == "table" then
			copy[param1] = Index.Client(param1, param2)
		else
			copy[param2] = Index.Client(param2)
		end
	end
	return copy
end

function Index.Signal(Identifier: string)
	Assert(typeof(Identifier) == "string", `Identifier must be a string type, got {typeof(Identifier)}`)
	Assert(Identifier ~= "", "Identifier cannot be an empty string")
	return Signal(Identifier)
end

function Index.fromSignalArray(arrays: { any })
	Assert(typeof(arrays) == "table", `Array must be a table type, got {typeof(arrays)}`)
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
