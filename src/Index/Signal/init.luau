--!strict
--!optimize 2
local Signal = {}
Signal.__index = Signal

local DedicatedSignal = require(script.Dedicated)

local Util = script.Parent.Util
local Key = require(Util.Key)
local Assert = require(Util.Assert)

local Signals = {}

function Signal.new(Identifier: string)
	Assert(typeof(Identifier) == "string", `Identifier must be a string type, got {typeof(Identifier)}`, 2)
	if not Signals[Identifier] then
		local signal = setmetatable({}, Signal)
		Signals[Identifier] = signal
		return signal
	end
	return Signals[Identifier]
end

function Signal:Connect(fn: (...any) -> (), optKey: string?): string
	local key: string = optKey or tostring(Key())
	self[key] = DedicatedSignal(self, fn)
	return key :: any
end

function Signal:Once(fn: (...any) -> ()): string
	local key: string
	key = self:Connect(function(...: any)
		self:Disconnect(key)
		task.spawn(fn, ...)
	end)
	return key
end

function Signal:Disconnect(key: string)
	if not self[key] then return end
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
	local to = Signals[signal]
	if not to then return end
	Signal.Fire(to, ...)
end

function Signal:Invoke(key: string, ...: any): ()
	local to = self[key]
	if not to then return end
	return to.fn(...)
end

function Signal:InvokeTo(signal: string, key: string, ...: any): ()
	if not Signals[signal] then return end
	return Signal.Invoke(Signals[signal], key, ...)
end

function Signal:Destroy(): ()
	self:DisconnectAll()
	setmetatable(self, nil)
end

return Signal.new :: typeof(Signal.new)