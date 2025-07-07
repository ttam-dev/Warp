--[[
	Client

	A class for managing client-side remote events and requests in Roblox, with support for reliable/unreliable messaging, and callback management.

	Constructor:
		Client.new(Identifier: string, conf: Type.ClientConf?)
			Creates a new Client instance with a unique identifier and optional configuration.

	Properties:
		id: string
			Unique identifier for the client instance.
		fn: { string }
			List of callback keys connected to this client.
		_conf: Type.ClientConf
			Configuration table for the client, frozen for immutability.
		IsConnected: boolean
			Indicates if there are any connected callbacks.

	Methods:
		Fire(reliable: boolean, ...: any)
			Sends a message to the server.

		Invoke(timeout: number, ...: any): any
			Sends a request to the server and waits for a response or timeout.

		Connect(callback: (args: any) -> ()): string
			Connects a callback to be called when the client receives a message. Returns a key for disconnection.

		Once(callback: (args: any) -> ()): string
			Connects a callback that will be called only once. Returns a key for disconnection.

		Wait(): number
			Yields the current thread until the client receives a message, then returns the elapsed time.

		DisconnectAll()
			Disconnects all connected callbacks.

		Disconnect(key: string)
			Disconnects a callback by its key.

		Destroy()
			Cleans up the client instance, disconnecting all callbacks and removing it from the process manager.

	Usage:
		local Client = require(path.to.Client)
		local myClient = Client("MyIdentifier", { yieldWait = 10 })
		myClient:Connect(function(...)
			-- handle event
		end)
]]
--!strict
--!native
--!optimize 2
local Client = {}
Client.__index = Client

local Util = script.Parent.Parent.Util

local Type = require(script.Parent.Parent.Type)
local ClientProcess = require(script.Parent.ClientProcess)
local Assert = require(Util.Assert)
local Key = require(Util.Key)
local Serdes = require(Util.Serdes)
local Buffer = require(Util.Buffer)

function Client.new(Identifier: string, conf: Type.ClientConf?)
	Assert(typeof(Identifier) == "string", "Identifier must be a string type.")
	Assert(Identifier ~= "", "Identifier must not be an empty string.")

	local _buffer = Buffer.new()
	_buffer:wu8(Serdes.increment(Identifier, conf and conf.yieldWait))

	local self = setmetatable({}, Client)
	self.id = Buffer.convert(_buffer:build())
	self.fn = {}
	self._conf = table.freeze(conf or {})
	self.IsConnected = false

	ClientProcess.add(self.id, Identifier, conf or { yieldWait = 10 })
	_buffer:remove()

	return self
end

function Client:Fire(reliable: boolean, ...: any)
	Assert(typeof(reliable) == "boolean", "Reliable must be a boolean type.")
	ClientProcess.insertQueue(self.id, reliable, ...)
end

function Client:Invoke(timeout: number, ...: any): any
	Assert(typeof(timeout) == "number", "Timeout must be a number type.")
	Assert(timeout >= 0, "Timeout must be a non-negative number.")
	return ClientProcess.insertRequest(self.id, timeout, ...)
end

function Client:Connect(callback: (args: any) -> ()): string
	Assert(typeof(callback) == "function", "Callback must be a function type.")
	local key = tostring(Key())
	table.insert(self.fn, key)
	self.IsConnected = #self.fn > 0
	ClientProcess.addCallback(self.id, key, callback)
	return key
end

function Client:Once(callback: (args: any) -> ()): string
	Assert(typeof(callback) == "function", "Callback must be a function type.")
	local key = tostring(Key())
	table.insert(self.fn, key)
	self.IsConnected = #self.fn > 0
	ClientProcess.addCallback(self.id, key, function(...: any?)
		self:Disconnect(key)
		task.spawn(callback, ...)
	end)
	return key
end

function Client:Wait()
	local thread: thread, t = coroutine.running(), os.clock()
	self:Once(function()
		task.spawn(thread, os.clock() - t)
	end)
	return coroutine.yield()
end

function Client:DisconnectAll()
	for _, key: string in self.fn do
		self:Disconnect(key)
	end
end

function Client:Disconnect(key: string)
	Assert(typeof(key) == "string", "Key must be a string type.")
	ClientProcess.removeCallback(self.id, key)
	table.remove(self.fn, table.find(self.fn, key))
	self.IsConnected = #self.fn > 0
end

function Client:Destroy()
	self:DisconnectAll()
	ClientProcess.remove(self.id)
	Serdes.decrement()
	table.clear(self)
	setmetatable(self, nil)
end

return Client.new
