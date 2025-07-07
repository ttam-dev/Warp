--!strict
--!optimize 2
local RateLimit = {}

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Assert = require(script.Parent.Assert)
local Events = require(script.Parent.Parent.Event)
local Reliable, Unreliable, Request = Events.Reliable, Events.Unreliable, Events.Request
local Signal = require(script.Parent.Parent.Signal)("Warp_OnSpamSignal")

local map, activity, meta = {}, {}, {}
local isServer = RunService:IsServer()
setmetatable(meta, {
	__index = map,
	__newindex = function(_, key, value)
		if typeof(value) ~= "number" then
			return
		end
		if not activity[key] then
			activity[key] = os.clock()
		end
		if (os.clock() - activity[key]) >= 1 then
			activity[key] = os.clock()
			map[key] = 1
			return
		end
		if value >= 1e2 then -- 100
			Signal:Fire(key)
			return
		end
		map[key] = value
	end,
})

local function onReceived(player: Player)
	if not meta[player] then
		meta[player] = 1
		return
	end
	meta[player] += 1
end

local function onPlayerLeave(player: Player)
	if meta[player] then
		meta[player] = nil
	end
	if activity[player] then
		activity[player] = nil
	end
	if map[player] then
		map[player] = nil
	end
end

function RateLimit.create(Identifier: string, entrance: number?, interval: number?)
	Assert(typeof(Identifier) == "string", "Identifier must a string type.")
	if isServer then
		Assert(typeof(entrance) == "number", "entrance must a number type.")
		Assert(entrance :: number > 0, "entrance must above 0.")
		Reliable:SetAttribute(Identifier .. "_ent", entrance)
		Reliable:SetAttribute(Identifier .. "_int", interval)
	else
		while (not Reliable:GetAttribute(Identifier .. "_ent")) or (not Reliable:GetAttribute(Identifier .. "_int")) do
			task.wait(0.1)
		end
		entrance = tonumber(Reliable:GetAttribute(Identifier .. "_ent"))
		interval = tonumber(Reliable:GetAttribute(Identifier .. "_int"))
	end
	local tokens = entrance :: number
	local lastTime = os.clock()
	local refillRate = tokens / (interval or 1)

	return function(incoming: number?): boolean
		local now = os.clock()
		local delta = now - lastTime
		lastTime = now

		-- Refill tokens based on elapsed time
		tokens = math.min(entrance :: number, tokens + delta * refillRate)

		-- Attempt to consume tokens
		local needed = incoming or 1
		if tokens >= needed then
			tokens -= needed
			return true
		else
			return false
		end
	end
end

function RateLimit.Protect()
	if
		not isServer
		or Reliable:GetAttribute("Protected")
		or Unreliable:GetAttribute("Protected")
		or Request:GetAttribute("Protected")
	then
		return
	end
	Reliable:SetAttribute("Protected", true)
	Unreliable:SetAttribute("Protected", true)
	Request:SetAttribute("Protected", true)
	Reliable.OnServerEvent:Connect(onReceived)
	Unreliable.OnServerEvent:Connect(onReceived)
	Request.OnServerEvent:Connect(onReceived)
end

function RateLimit.isPlayerReachingLimit(player: Player): boolean
	Assert(isServer, "RateLimit.isPlayerReachingLimit can only be called on the server.")
	Assert(typeof(player) == "Instance" and player:IsA("Player"), "Expected a Player instance.")
	if not meta[player] then
		return false
	end
	return meta[player] >= 100 -- 100 is the threshold for spam detection
end

Players.PlayerRemoving:Connect(onPlayerLeave)

return RateLimit :: typeof(RateLimit)
