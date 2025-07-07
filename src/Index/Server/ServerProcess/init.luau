--!native
--!strict
--!optimize 2
local ServerProcess = {}

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Util = script.Parent.Parent.Util

local Type = require(script.Parent.Parent.Type)
local Event = require(script.Parent.Parent.Event)
local Spawn = require(Util.Spawn)
local Key = require(Util.Key)
local RateLimit = require(Util.RateLimit)
local Buffer = require(Util.Buffer)
local myTablesUtils = require(Util.myTableUtils)
local clearEntry = myTablesUtils.clearEntry

local serverQueue: Type.QueueMap = {}
local unreliableServerQueue: Type.QueueMap = {}
local serverCallback: Type.CallbackMap = {}
local serverRequestQueue: Type.QueueMap = {}
local registeredIdentifier: { [string]: boolean } = {}

local queueOut: {
	[Player]: {
		[string]: { any },
	},
} = {}
local queueInRequest: {
	[number]: {
		[string]: {
			[Player]: { any },
		},
	},
} = {}
local queueOutRequest: {
	[number]: {
		[string]: {
			[Player]: { any },
		},
	},
} = {}

queueInRequest[1] = {}
queueInRequest[2] = {}
queueOutRequest[1] = {}
queueOutRequest[2] = {}

local ReliableEvent = Event.Reliable
local UnreliableEvent = Event.Unreliable
local RequestEvent = Event.Request

RateLimit.Protect()

local function initializeEachPlayer(player: Player)
	if not player then
		return
	end
	if not queueOut[player] then
		queueOut[player] = {}
	end
	for Identifier: string in registeredIdentifier do
		if not player then
			break
		end
		if not queueOut[player][Identifier] then
			queueOut[player][Identifier] = {}
		end
		if not serverRequestQueue[Identifier] then
			serverRequestQueue[Identifier] = {}
		end
		if not serverRequestQueue[Identifier][player] then
			serverRequestQueue[Identifier][player] = {}
		end
		if not queueOutRequest[1][Identifier] then
			queueOutRequest[1][Identifier] = {}
		end
		if not queueOutRequest[2][Identifier] then
			queueOutRequest[2][Identifier] = {}
		end
		if not queueInRequest[1][Identifier][player] then
			queueInRequest[1][Identifier][player] = {}
			queueInRequest[2][Identifier][player] = {}
		end
		if not queueOutRequest[1][Identifier][player] then
			queueOutRequest[1][Identifier][player] = {}
			queueOutRequest[2][Identifier][player] = {}
		end
	end
end

local function onPlayerLeave(player: Player)
	if not player then
		return
	end
	if queueOut[player] then
		clearEntry(queueOut, player)
	end
	for _, map in { serverQueue, unreliableServerQueue, serverRequestQueue } do
		for Identifier: string in map do
			if map[Identifier][player] then
				clearEntry(map[Identifier], player)
			end
		end
	end
	for i = 1, 2 do
		for Identifier: string in queueInRequest[i] do
			if queueInRequest[i][Identifier][player] then
				clearEntry(queueInRequest[i][Identifier], player)
			end
		end
		for Identifier: string in queueOutRequest[i] do
			if queueOutRequest[i][Identifier][player] then
				clearEntry(queueOutRequest[i][Identifier], player)
			end
		end
	end
end

local function processUnreliable()
	for Identifier: string, players in unreliableServerQueue do
		for player: Player, content: any in players do
			if #content == 0 then
				continue
			end
			for _, unpacked in content do
				UnreliableEvent:FireClient(player, Buffer.revert(Identifier), Buffer.write(unpacked))
			end
			table.clear(unreliableServerQueue[Identifier][player])
		end
	end
end

local function processReliable()
	for Identifier: string, contents: { [Player]: { any } } in serverQueue do
		for player, content: any in contents do
			if #content > 0 and queueOut[player] then
				for _, unpacked in content do
					ReliableEvent:FireClient(player, Buffer.revert(Identifier), Buffer.write(unpacked))
				end
			end
			table.clear(serverQueue[Identifier][player])
		end
	end
end

local function processRequest()
	-- Sent new and returning invokes in a single loop
	for i = 1, 2 do
		local action = i == 1 and "\1" or "\0"
		local queue = queueOutRequest[i]
		for Identifier: string, contents in queue do
			for player: Player, data: any in contents do
				if #data > 0 then
					RequestEvent:FireClient(player, Buffer.revert(Identifier), action, data)
				end
				table.clear(queue[Identifier][player])
			end
		end
	end

	for Identifier: string in registeredIdentifier do
		if serverRequestQueue[Identifier] then
			for player, content in serverRequestQueue[Identifier] do
				if #content == 0 then
					serverRequestQueue[Identifier][player] = nil
					continue
				end
				for _, requestData in content do
					if not requestData[3] then
						continue
					end
					if not queueOutRequest[1][Identifier] then
						queueOutRequest[1][Identifier] = {}
					end
					if not queueOutRequest[1][Identifier][player] then
						queueOutRequest[1][Identifier][player] = {}
					end
					table.insert(queueOutRequest[1][Identifier][player], { requestData[1], requestData[3] })
					requestData[3] = nil
				end
			end
		end

		local callback = serverCallback[Identifier] or nil
		if not callback then
			continue
		end

		-- Return Invoke
		for player, content in queueInRequest[1][Identifier] do
			if not callback then
				break
			end
			for _, packetDatas in content do
				if not callback then
					break
				end
				if #packetDatas == 0 then
					continue
				end
				for _, fn: any in callback do
					for i = 1, #packetDatas do
						if not packetDatas[i] then
							continue
						end
						local packetData1 = packetDatas[i][1]
						local packetData2 = packetDatas[i][2]
						Spawn(function()
							local requestReturn = { fn(player, table.unpack(packetData2)) }
							if not queueOutRequest[2][Identifier] then
								queueOutRequest[2][Identifier] = {}
							end
							if not queueOutRequest[2][Identifier][player] then
								queueOutRequest[2][Identifier][player] = {}
							end
							table.insert(queueOutRequest[2][Identifier][player], { packetData1, requestReturn })
							packetData1 = nil
							packetData2 = nil
						end)
					end
				end
			end
			table.clear(queueInRequest[1][Identifier][player])
		end

		-- Call to Invoke
		for player, content in queueInRequest[2][Identifier] do
			if not callback then
				break
			end
			for _, packetDatas in content do
				for _, packetData in packetDatas do
					if not callback then
						break
					end
					if #packetData == 1 then
						continue
					end
					local data = serverRequestQueue[Identifier][player]
					for i = 1, #data do
						local serverRequest = data[i]
						if not serverRequest then
							continue
						end
						if serverRequest[1] == packetData[1] then
							Spawn(serverRequest[2], table.unpack(packetData[2]))
							table.remove(data, i)
							break
						end
					end
				end
			end
			table.clear(queueInRequest[2][Identifier][player])
		end
	end
end

local function onServerNetworkReceive(player: Player, Identifier: buffer | string, data: buffer, ref: { any }?)
	if not Identifier or typeof(Identifier) ~= "buffer" or not data or typeof(data) ~= "buffer" then
		return
	end
	if RateLimit.isPlayerReachingLimit(player) then
		return
	end
	Identifier = Buffer.convert(Identifier :: buffer)
	if typeof(Identifier) ~= "string" then
		return
	end
	if not registeredIdentifier[Identifier :: string] then
		return
	end
	local read = Buffer.read(data, ref)
	if not read then
		return
	end
	local callback = serverCallback[Identifier :: string]
	if not callback then
		return
	end
	for _, fn: any in callback do
		Spawn(fn, player, table.unpack(read))
	end
end

local function onServerRequestReceive(player: Player, Identifier: any, action: string, data: any)
	if not Identifier or not data then
		return
	end
	if RateLimit.isPlayerReachingLimit(player) then
		return
	end
	Identifier = Buffer.convert(Identifier)
	if typeof(Identifier) ~= "string" then
		return
	end
	if not registeredIdentifier[Identifier :: string] then
		return
	end
	if not queueInRequest[1][Identifier][player] then
		queueInRequest[1][Identifier][player] = {}
	end
	if not queueInRequest[2][Identifier][player] then
		queueInRequest[2][Identifier][player] = {}
	end
	if not serverQueue[Identifier] then
		serverQueue[Identifier] = {}
	end
	if not serverQueue[Identifier][player] then
		serverQueue[Identifier][player] = {}
	end
	if action == "\1" then
		table.insert(queueInRequest[1][Identifier][player], data)
	else
		table.insert(queueInRequest[2][Identifier][player], data)
	end
end

function ServerProcess.insertQueue(Identifier: string, reliable: boolean, player: Player, ...: any)
	if not reliable then
		if not unreliableServerQueue[Identifier] then
			unreliableServerQueue[Identifier] = {}
		end
		if not unreliableServerQueue[Identifier][player] then
			unreliableServerQueue[Identifier][player] = {}
		end
		table.insert(unreliableServerQueue[Identifier][player], { ... })
		return
	end
	if not serverQueue[Identifier] then
		serverQueue[Identifier] = {}
	end
	if not serverQueue[Identifier][player] then
		serverQueue[Identifier][player] = {}
	end
	table.insert(serverQueue[Identifier][player], { ... })
end

function ServerProcess.insertRequest(Identifier: string, timeout: number, player: Player, ...: any)
	if not serverRequestQueue[Identifier] then
		serverRequestQueue[Identifier] = {}
	end
	if not serverRequestQueue[Identifier][player] then
		serverRequestQueue[Identifier][player] = {}
	end
	local yieldThread: thread, start = coroutine.running(), os.clock()
	local cancel = task.delay(timeout, function()
		task.spawn(yieldThread, nil)
	end)
	table.insert(serverRequestQueue[Identifier][player], {
		tostring(Key()),
		function(...: any)
			if (os.clock() - start) > timeout then
				return
			end
			task.cancel(cancel)
			task.spawn(yieldThread, ...)
		end :: any,
		{ ... } :: any,
	})
	return coroutine.yield()
end

function ServerProcess.add(Identifier: string, originId: string, conf: Type.ServerConf)
	if not registeredIdentifier[Identifier] then
		registeredIdentifier[Identifier] = true

		RateLimit.create(
			originId,
			conf.rateLimit and conf.rateLimit.maxEntrance or 100,
			conf.rateLimit and conf.rateLimit.interval or 1
		)

		if not serverQueue[Identifier] then
			serverQueue[Identifier] = {}
		end
		if not serverRequestQueue[Identifier] then
			serverRequestQueue[Identifier] = {}
		end
		if not serverCallback[Identifier] then
			serverCallback[Identifier] = {}
		end
		if not unreliableServerQueue[Identifier] then
			unreliableServerQueue[Identifier] = {}
		end

		if not queueInRequest[1][Identifier] then
			queueInRequest[1][Identifier] = {}
		end
		if not queueInRequest[2][Identifier] then
			queueInRequest[2][Identifier] = {}
		end
		if not queueOutRequest[1][Identifier] then
			queueOutRequest[1][Identifier] = {}
		end
		if not queueOutRequest[2][Identifier] then
			queueOutRequest[2][Identifier] = {}
		end

		for _, player: Player in ipairs(Players:GetPlayers()) do
			task.spawn(initializeEachPlayer, player)
		end
	end
end

function ServerProcess.remove(Identifier: string)
	if not registeredIdentifier[Identifier] then
		return
	end

	registeredIdentifier[Identifier] = nil

	local maps = {
		serverQueue,
		unreliableServerQueue,
		serverRequestQueue,
		queueInRequest[1],
		queueInRequest[2],
		queueOutRequest[1],
		queueOutRequest[2],
		serverCallback,
	}

	for _, map in ipairs(maps) do
		clearEntry(map, Identifier)
	end
end

function ServerProcess.addCallback(Identifier: string, key: string, callback)
	serverCallback[Identifier][key] = callback
end

function ServerProcess.removeCallback(Identifier: string, key: string)
	serverCallback[Identifier][key] = nil
end

function ServerProcess.start()
	for _, player: Player in ipairs(Players:GetPlayers()) do
		task.spawn(initializeEachPlayer, player)
	end

	Players.PlayerAdded:Connect(initializeEachPlayer)
	Players.PlayerRemoving:Connect(onPlayerLeave)

	debug.setmemorycategory("Warp.Server")
	RunService.PostSimulation:Connect(function()
		processUnreliable()
		processReliable()
		processRequest()
	end)

	ReliableEvent.OnServerEvent:Connect(onServerNetworkReceive)
	UnreliableEvent.OnServerEvent:Connect(onServerNetworkReceive)
	RequestEvent.OnServerEvent:Connect(onServerRequestReceive)
end

return ServerProcess
