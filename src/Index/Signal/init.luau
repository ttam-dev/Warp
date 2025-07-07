--[[
	Signal

	A signal implementation for event-driven programming in Roblox. It allows for connecting, disconnecting, and firing callbacks with support for deferred execution and invocation.

	Constructor:
		Signal.new(Identifier: string): Signal
			Creates a new signal instance with a unique identifier. If an instance with the same identifier already exists, it returns that instance.

	Properties:

	Methods:
		Connect(fn: (...any) -> (), optKey: string?): string
			Connects a callback function to the signal. Returns a key for disconnection.

		Once(fn: (...any) -> ()): string
			Connects a callback that will be called only once. Returns a key for disconnection.

		Disconnect(key: string)
			Disconnects a callback by its key.

		DisconnectAll()
			Disconnects all connected callbacks.

		Wait(): number
			Yields the current thread until the signal is fired, then returns the elapsed time.

		DeferFire(...: any): ()
			Fires the signal with deferred execution for each connected callback.

		Fire(...: any): ()
			Fires the signal immediately for each connected callback.

		FireTo(signal: string, ...: any): ()
			Fires the signal to another signal instance identified by `signal`.

		Invoke(key: string, ...: any): ()
			Synchronously invokes a callback by its key and returns its result.

		InvokeTo(signal: string, key: string, ...: any): ()
			Synchronously invokes a callback in another signal instance identified by `signal` and `key`.

		Destroy(): ()
			Cleans up the signal instance, disconnecting all callbacks and removing it from the process manager.

	Usage:
		local Signal = require(path.to.Signal)
		local mySignal = Signal.new("MySignal")
		local key = mySignal:Connect(function(...)
			-- handle signal
		end)
		mySignal:Fire("Hello", "World")
]]
--!strict
--!native
--!optimize 2
local Signal = {}
Signal.__index = Signal

local DedicatedSignal = require(script.Dedicated)

local Util = script.Parent.Util
local Key = require(Util.Key)
local Assert = require(Util.Assert)

local Signals = {}

function Signal.new(Identifier: string)
	Assert(typeof(Identifier) == "string", `Identifier must be a string type, got {typeof(Identifier)}`)
	Assert(Identifier ~= "", "Identifier cannot be an empty string")
	if not Signals[Identifier] then
		local signal = setmetatable({}, Signal)
		Signals[Identifier] = signal
		return signal
	end
	return Signals[Identifier]
end

function Signal:Connect(fn: (...any) -> (), optKey: string?): string
	Assert(typeof(fn) == "function", `Callback must be a function, got {typeof(fn)}`)
	Assert(not self[optKey], `Signal already has a connection with key {optKey}`)
	local key: string = optKey or tostring(Key())
	self[key] = DedicatedSignal(self, fn)
	return key
end

function Signal:Once(fn: (...any) -> ()): string
	Assert(typeof(fn) == "function", `Callback must be a function, got {typeof(fn)}`)
	local key: string
	key = self:Connect(function(...: any)
		self:Disconnect(key)
		task.spawn(fn, ...)
	end)
	return key
end

function Signal:Disconnect(key: string)
	Assert(typeof(key) == "string", `Key must be a string type, got {typeof(key)}`)
	Assert(self[key], `Signal does not have a connection with key {key}`)
	self[key]:Disconnect()
	self[key] = nil
end

function Signal:DisconnectAll(): ()
	table.clear(self)
end

function Signal:Wait(): number
	local t, thread = os.clock(), coroutine.running()
	self:Once(function()
		task.spawn(thread, os.clock()-t)
	end)
	return coroutine.yield()
end

function Signal:DeferFire(...: any): ()
	for _, handle in self do
		task.defer(handle.fn, ...)
	end
end

function Signal:Fire(...: any): ()
	for _, handle in self do
		task.spawn(handle.fn, ...)
	end
end

function Signal:FireTo(signal: string, ...: any): ()
	Assert(typeof(signal) == "string", `Signal name must be a string type, got {typeof(signal)}`)
	Assert(Signals[signal], `Signal {signal} does not exist`)
	local to = Signals[signal]
	Signal.Fire(to, ...)
end

function Signal:Invoke(key: string, ...: any): ()
	Assert(typeof(key) == "string", `Key must be a string type, got {typeof(key)}`)
	Assert(self[key], `Signal does not have a connection with key {key}`)
	local to = self[key]
	return to.fn(...)
end

function Signal:InvokeTo(signal: string, key: string, ...: any): ()
	Assert(typeof(signal) == "string", `Signal name must be a string type, got {typeof(signal)}`)
	Assert(typeof(key) == "string", `Key must be a string type, got {typeof(key)}`)
	Assert(Signals[signal], `Signal {signal} does not exist`)
	return Signal.Invoke(Signals[signal], key, ...)
end

function Signal:Destroy(): ()
	self:DisconnectAll()
	setmetatable(self, nil)
end

return Signal.new :: typeof(Signal.new)