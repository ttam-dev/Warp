--!strict
--!native
--!optimize 2

local Signal = {}
Signal.__index = Signal

local SignalPlus = require(script.SignalPlus)

local Util = script.Parent.Util
local Key = require(Util.Key)
local Assert = require(Util.Assert)

-- Type definition for the Signal object
type Signal = {
	_core: any,
	_connections: { [string]: any },
	_id: string,

	Connect: (self: Signal, fn: (...any) -> (), optKey: string?) -> string,
	Once: (self: Signal, fn: (...any) -> ()) -> string,
	Disconnect: (self: Signal, key: string) -> (),
	DisconnectAll: (self: Signal) -> (),
	Wait: (self: Signal) -> (...any),
	DeferFire: (self: Signal, ...any) -> (),
	Fire: (self: Signal, ...any) -> (),
	FireTo: (self: Signal, signalId: string, ...any) -> (),
	Invoke: (self: Signal, key: string, ...any) -> (...any)?,
	InvokeTo: (self: Signal, signalId: string, key: string, ...any) -> (...any)?,
	Destroy: (self: Signal) -> ()
}

local Signals: { [string]: Signal } = {}

function Signal.new(identifier: string): Signal
	Assert(typeof(identifier) == "string", `[Signal]: Identifier must be a string, got {typeof(identifier)}`)

	if not Signals[identifier] then
		local self = setmetatable({}, Signal) :: any
		local core = SignalPlus()
		Assert(type(core.Connect) == "function", "[Signal]: Invalid SignalPlus core object")
		self._core = core
		self._connections = {}
		self._id = identifier
		Signals[identifier] = self
	end

	return Signals[identifier]
end

function Signal:Connect(fn: (...any) -> (), optKey: string?): string
	local key = optKey or tostring(Key())
	self._connections[key] = self._core:Connect(fn)
	return key
end

function Signal:Once(fn: (...any) -> ()): string
	local key = ""
	key = self:Connect(function(...: any)
		self:Disconnect(key)
		task.spawn(fn, ...)
	end)
	return key
end

function Signal:Disconnect(key: string)
	local conn = self._connections[key]
	if conn then
		conn:Disconnect()
		self._connections[key] = nil
	end
end

function Signal:DisconnectAll()
	for key, conn in pairs(self._connections) do
		conn:Disconnect()
	end
	table.clear(self._connections)
end

function Signal:Wait(): ...any
	return self._core:Wait()
end

function Signal:DeferFire(...: any)
	for _, conn in pairs(self._connections) do
		local handler = (conn :: any)._handler
		if type(handler) == "function" then
			task.defer(handler, ...)
		end
	end
end

function Signal:Fire(...: any)
	self._core:Fire(...)
end

function Signal:FireTo(signalId: string, ...: any)
	local target = Signals[signalId]
	if target then
		target:Fire(...)
	end
end

function Signal:Invoke(key: string, ...: any): ...any
	local conn = self._connections[key]
	local handler = conn and (conn :: any)._handler
	if type(handler) == "function" then
		return handler(...)
	end
end

function Signal:InvokeTo(signalId: string, key: string, ...: any): ...any
	local target = Signals[signalId]
	if target then
		local invoke = target.Invoke -- bind method to local variable
		if invoke then
			return invoke(target, key, ...) -- call using dot-syntax with self manually
		end
	end
end

function Signal:Destroy()
	self:DisconnectAll()
	self._core = nil
	self._connections = nil
	Signals[self._id] = nil
	setmetatable(self, nil)
end

return Signal.new :: typeof(Signal.new)
