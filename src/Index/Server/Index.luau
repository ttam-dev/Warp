--[[
	Server

	A class for managing server-side remote events and requests in Roblox, with support for rate limiting, reliable/unreliable messaging, and callback management.

	Constructor:
		Server.new(Identifier: string, conf: Type.ServerConf?)
			Creates a new Server instance with a unique identifier and optional configuration.

	Properties:
		id: string
			Unique identifier for the server instance.
		fn: { string }
			List of callback keys connected to this server.
		_conf: Type.ServerConf
			Configuration table for the server, frozen for immutability.
		IsConnected: boolean
			Indicates if there are any connected callbacks.

	Methods:
		Fire(reliable: boolean, player: Player, ...: any)
			Sends a message to a specific player.

		FireAll(reliable: boolean, ...: any)
			Sends a message to all players.

		FireAllExcept(reliable: boolean, except: { Player }, ...: any)
			Sends a message to all players except those specified.

		FireAllIn(reliable: boolean, range: number, from: Vector3, data: { any }, except: { Player }?)
			Sends a message to all players within a certain range from a position, optionally excluding some players.

		Invoke(timeout: number, player: Player, ...: any): any
			Sends a request to a player and waits for a response or timeout.

		Connect(callback: (player: Player, args: any) -> ()): string
			Connects a callback to be called when the server receives a message. Returns a key for disconnection.

		Once(callback: (player: Player, args: any) -> ()): string
			Connects a callback that will be called only once. Returns a key for disconnection.

		Wait(): number
			Yields the current thread until the server receives a message, then returns the elapsed time.

		DisconnectAll()
			Disconnects all connected callbacks.

		Disconnect(key: string): boolean
			Disconnects a callback by its key. Returns true if successful.

		Destroy()
			Cleans up the server instance, disconnecting all callbacks and removing it from the process manager.

	Usage:
		local Server = require(path.to.Server)
		local myServer = Server("MyIdentifier", { rateLimit = { maxEntrance = 100, interval = 1 } })
		myServer:Connect(function(player, ...)
			-- handle event
		end)
]]
--!strict
--!native
--!optimize 2
local Server = {}
Server.__index = Server

local Players = game:GetService("Players")
local Util = script.Parent.Parent.Util

local Type = require(script.Parent.Parent.Type)
local ServerProcess = require(script.Parent.ServerProcess)
local Assert = require(Util.Assert)
local Key = require(Util.Key)
local Serdes = require(Util.Serdes)
local Buffer = require(Util.Buffer)

function Server.new(Identifier: string, conf: Type.ServerConf?)
	Assert(typeof(Identifier) == "string", "Identifier must be a string type.")
	Assert(Identifier ~= "", "Identifier must not be an empty string.")

	local _buffer = Buffer.new()
	_buffer:wu8(Serdes.increment(Identifier))

	local self = setmetatable({}, Server)
	self.id = Buffer.convert(_buffer:build())
	self.fn = {}
	self._conf = table.freeze(conf or {})
	self.IsConnected = false

	ServerProcess.add(self.id, Identifier, conf or { rateLimit = { maxEntrance = 100, interval = 1 } })
	_buffer:remove()

	return self
end

function Server:Fire(reliable: boolean, player: Player, ...: any)
	Assert(typeof(reliable) == "boolean", "Reliable must be a boolean type.")
	Assert(typeof(player) == "Instance" and player:IsA("Player"), "Player must be a Player instance.")
	Assert(player:IsDescendantOf(Players), "Player must be a descendant of Players.")
	ServerProcess.insertQueue(self.id, reliable, player, ...)
end

function Server:FireAll(reliable: boolean, ...: any)
	Assert(typeof(reliable) == "boolean", "Reliable must be a boolean type.")
	for _, player: Player in ipairs(Players:GetPlayers()) do
		ServerProcess.insertQueue(self.id, reliable, player, ...)
	end
end

function Server:FireAllExcept(reliable: boolean, except: { Player }, ...: any)
	Assert(typeof(reliable) == "boolean", "Reliable must be a boolean type.")
	Assert(typeof(except) == "table", "Except must be a table type.")
	Assert(#except > 0, "Except table must not be empty.")
	for _, player: Player in ipairs(Players:GetPlayers()) do
		if table.find(except, player) then
			continue
		end
		ServerProcess.insertQueue(self.id, reliable, player, ...)
	end
end

function Server:FireAllIn(reliable: boolean, range: number, from: Vector3, data: { any }, except: { Player }?)
	Assert(typeof(reliable) == "boolean", "Reliable must be a boolean type.")
	Assert(typeof(range) == "number", "Range must be a number type.")
	Assert(range >= 0, "Range must be greater than or equal to 0.")
	Assert(typeof(from) == "Vector3", "From must be a Vector3 type.")
	Assert(typeof(data) == "table", "Data must be a table type.")
	Assert(#data > 0, "Data table must not be empty.")
	Assert(except == nil or typeof(except) == "table", "Except must be a table type or nil.")
	Assert(except == nil or #except > 0, "Except table must not be empty.")
	for _, player: Player in ipairs(Players:GetPlayers()) do
		if
			(except and table.find(except, player))
			or not player.Character
			or not player.Character.PrimaryPart
			or (player.Character.PrimaryPart.Position - from).Magnitude < range
		then
			continue
		end
		ServerProcess.insertQueue(self.id, reliable, player, table.unpack(data))
	end
end

function Server:Invoke(timeout: number, player: Player, ...: any): any
	Assert(typeof(timeout) == "number", "Timeout must be a number type.")
	Assert(timeout >= 0, "Timeout must be greater than or equal to 0.")
	Assert(typeof(player) == "Instance" and player:IsA("Player"), "Player must be a Player instance.")
	Assert(player:IsDescendantOf(Players), "Player must be a descendant of Players.")
	return ServerProcess.insertRequest(self.id, timeout, player, ...)
end

function Server:Connect(callback: (plyer: Player, args: any) -> ()): string
	Assert(typeof(callback) == "function", "Callback must be a function type.")
	local key = tostring(Key())
	table.insert(self.fn, key)
	ServerProcess.addCallback(self.id, key, callback)
	self.IsConnected = #self.fn > 0
	return key
end

function Server:Once(callback: (plyer: Player, args: any) -> ()): string
	Assert(typeof(callback) == "function", "Callback must be a function type.")
	local key = tostring(Key())
	table.insert(self.fn, key)
	self.IsConnected = #self.fn > 0
	ServerProcess.addCallback(self.id, key, function(player: Player, ...: any?)
		self:Disconnect(key)
		task.spawn(callback, player, ...)
	end)
	return key
end

function Server:Wait()
	local thread: thread, t = coroutine.running(), os.clock()
	self:Once(function()
		task.spawn(thread, os.clock() - t)
	end)
	return coroutine.yield()
end

function Server:DisconnectAll()
	for _, key: string in self.fn do
		self:Disconnect(key)
	end
end

function Server:Disconnect(key: string): boolean
	Assert(typeof(key) == "string", "Key must be a string type.")
	ServerProcess.removeCallback(self.id, key)
	table.remove(self.fn, table.find(self.fn, key))
	self.IsConnected = #self.fn > 0
	return table.find(self.fn, key) == nil
end

function Server:Destroy()
	self:DisconnectAll()
	ServerProcess.remove(self.id)
	Serdes.decrement()
	table.clear(self)
	setmetatable(self, nil)
end

return Server.new
