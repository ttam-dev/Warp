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
local Assert = require(Util.Assert)
local myTableUtils = require(Util.myTableUtils)
local ensure = myTableUtils.ensure
local recycle = myTableUtils.recycle
local clear = myTableUtils.clear

local serverQueue: Type.QueueMap = {}
local unreliableServerQueue: Type.QueueMap = {}
local serverCallback: Type.CallbackMap = {}
local serverRequestQueue: Type.QueueMap = {}
local registeredIdentifier: { [string]: boolean } = {}

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
	if not next(registeredIdentifier) then
		return
	end
	for Identifier: string in registeredIdentifier do
		if not player then
			break
		end
		ensure(serverRequestQueue, Identifier)
		ensure(serverRequestQueue[Identifier], player)
		ensure(queueOutRequest[1], Identifier)
		ensure(queueOutRequest[2], Identifier)
		ensure(queueInRequest[1][Identifier], player)
		ensure(queueInRequest[2][Identifier], player)
		ensure(queueOutRequest[1][Identifier], player)
		ensure(queueOutRequest[2][Identifier], player)
	end
end

local function onPlayerLeave(player: Player)
	if not player then
		return
	end
	for _, map in { serverQueue, unreliableServerQueue, serverRequestQueue } do
		for Identifier: string in map do
			clear(map[Identifier], player)
		end
	end
	for i = 1, 2 do
		for Identifier: string in queueInRequest[i] do
			if queueInRequest[i][Identifier][player] then
				clear(queueInRequest[i][Identifier], player)
			end
		end
		for Identifier: string in queueOutRequest[i] do
			if queueOutRequest[i][Identifier][player] then
				clear(queueOutRequest[i][Identifier], player)
			end
		end
	end
end

local function processUnreliable()
	for Identifier: string, players in unreliableServerQueue do
		for player: Player, content: any in players do
			if #content > 0 then
				for _, unpacked in content do
					UnreliableEvent:FireClient(player, Buffer.revert(Identifier), Buffer.write(unpacked))
				end

				recycle(unreliableServerQueue[Identifier][player])
			end
		end
	end
end

local function processReliable()
	for Identifier: string, contents: { [Player]: { any } } in serverQueue do
		for player, content: any in contents do
			if #content > 0 then
				for _, unpacked in content do
					ReliableEvent:FireClient(player, Buffer.revert(Identifier), Buffer.write(unpacked))
				end

				recycle(serverQueue[Identifier][player])
			end
		end
	end
end

local function processOutboundRequests()
	for i = 1, 2 do
		local action = i == 1 and "\1" or "\0"
		local queue = queueOutRequest[i]
		for Identifier: string, contents: { [Player]: { any } } in queue do
			for player: Player, data: any in contents do
				if #data > 0 then
					RequestEvent:FireClient(player, Buffer.revert(Identifier), action, data)
					recycle(queue[Identifier][player])
				end
			end
		end
	end
end

local function processInboundRequests()
	for Identifier: string in registeredIdentifier do
		if serverRequestQueue[Identifier] then
			for player, content in serverRequestQueue[Identifier] do
				if #content == 0 then -- serverRequestQueue[Identifier][player] == {}
					continue
				end

				for _, requestData in content do
					if not requestData[3] then
						continue
					end
					ensure(queueOutRequest[1], Identifier)
					ensure(queueOutRequest[1][Identifier], player)
					table.insert(queueOutRequest[1][Identifier][player], { requestData[1], requestData[3] })
					table.remove(requestData, 3) -- remove the data from the request queue
				end
			end
		end

		local callback = serverCallback[Identifier] or nil
		if not callback or typeof(callback) ~= "function" then
			continue
		end

		-- Return Invoke
		for player, content in queueInRequest[1][Identifier] do
			for _, packetDatas in content do
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
							local ok, result = pcall(fn, player, table.unpack(packetData2))
							if ok then
								result = { result }
								ensure(queueOutRequest[2], Identifier)
								ensure(queueOutRequest[2][Identifier], player)
								table.insert(queueOutRequest[2][Identifier][player], { packetData1, result })
							else
								Assert(false, `Error in callback for {Identifier}: {result}`, 2)
							end
						end)
					end
				end
			end

			recycle(queueInRequest[1][Identifier][player]) --> {}
		end

		-- Call to Invoke
		for player, content in queueInRequest[2][Identifier] do
			local data = serverRequestQueue[Identifier][player]
			if not data then
				continue
			end
			for _, packetDatas in content do
				for _, packetData in packetDatas do
					if #packetData == 1 then
						continue
					end
					for i = 1, #data do
						local serverRequest = data[i]
						if not serverRequest then
							continue
						end
						if serverRequest[1] == packetData[1] then
							Spawn(serverRequest[1], player, table.unpack(packetData[2]))
							table.remove(data, i)
							break
						end
					end
				end
			end

			recycle(queueInRequest[2][Identifier][player]) --> {}
		end
	end
end

local function onServerNetworkReceive(player: Player, Identifier: buffer | string, data: buffer, ref: { any }?)
	if not Identifier or typeof(Identifier) ~= "buffer" or not data or typeof(data) ~= "buffer" then
		return
	end
	Identifier = Buffer.convert(Identifier :: buffer)
	if typeof(Identifier) ~= "string" then
		return
	end -- ensure it's string
	Assert(registeredIdentifier[Identifier], `Identifier {Identifier} is not registered.`, 2)
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
	Identifier = Buffer.convert(Identifier)
	if typeof(Identifier) ~= "string" then
		return
	end -- ensure it's string
	Assert(registeredIdentifier[Identifier], `Identifier {Identifier} is not registered.`, 2)
	if action == "\1" then
		ensure(queueInRequest[1], Identifier)
		ensure(queueInRequest[1][Identifier], player)
		table.insert(queueInRequest[1][Identifier][player], data)
	else
		ensure(queueInRequest[2], Identifier)
		ensure(queueInRequest[2][Identifier], player)
		table.insert(queueInRequest[2][Identifier][player], data)
	end
end

function ServerProcess.insertQueue(Identifier: string, reliable: boolean, player: Player, ...: any)
	if not reliable then
		ensure(unreliableServerQueue, Identifier)
		ensure(unreliableServerQueue[Identifier], player)
		-- these 2 table should be {} --> 0 or > 0
		table.insert(unreliableServerQueue[Identifier][player], { ... })
		return
	end
	ensure(serverQueue, Identifier)
	ensure(serverQueue[Identifier], player)
	-- these 2 table should be {} --> 0 or > 0
	table.insert(serverQueue[Identifier][player], { ... })
end

function ServerProcess.insertRequest(Identifier: string, timeout: number, player: Player, ...: any)
	ensure(serverRequestQueue, Identifier)
	ensure(serverRequestQueue[Identifier], player)
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
			conf.rateLimit and conf.rateLimit.maxEntrance or 200,
			conf.rateLimit and conf.rateLimit.interval or 2
		)

		ensure(serverQueue, Identifier)
		ensure(serverRequestQueue, Identifier)
		ensure(serverCallback, Identifier)
		ensure(unreliableServerQueue, Identifier)

		ensure(queueInRequest[1], Identifier)
		ensure(queueInRequest[2], Identifier)
		ensure(queueOutRequest[1], Identifier)
		ensure(queueOutRequest[2], Identifier)

		for _, player: Player in ipairs(Players:GetPlayers()) do
			task.spawn(initializeEachPlayer, player) -- update new indentifier for each player
		end
	end
end

function ServerProcess.remove(Identifier: string)
	Assert(registeredIdentifier[Identifier], `Identifier {Identifier} is not registered.`, 2)
	clear(registeredIdentifier, Identifier)
	clear(serverQueue, Identifier)
	clear(serverRequestQueue, Identifier)
	clear(serverCallback, Identifier)
	clear(unreliableServerQueue, Identifier)
	clear(queueInRequest[1], Identifier)
	clear(queueInRequest[2], Identifier)
	clear(queueOutRequest[1], Identifier)
	clear(queueOutRequest[2], Identifier)
end

function ServerProcess.addCallback(Identifier: string, key: string, callback)
	serverCallback[Identifier][key] = callback
end

function ServerProcess.removeCallback(Identifier: string, key: string)
	serverCallback[Identifier][key] = nil
end

function ServerProcess.start()
	-- Initialize for each player in server before any player joins
	for _, player: Player in ipairs(Players:GetPlayers()) do
		task.spawn(initializeEachPlayer, player)
	end

	-- Connect player added and removing events
	-- to ensure that new players get the correct queues and callbacks
	Players.PlayerAdded:Connect(initializeEachPlayer)
	Players.PlayerRemoving:Connect(onPlayerLeave)

	-- Connect the events
	ReliableEvent.OnServerEvent:Connect(onServerNetworkReceive)
	UnreliableEvent.OnServerEvent:Connect(onServerNetworkReceive)
	RequestEvent.OnServerEvent:Connect(onServerRequestReceive)

	-- Set up the RunService to process the queues
	debug.setmemorycategory("Warp.ServerProcess")
	RunService.PostSimulation:Connect(function()
		processUnreliable()
		processReliable()
		processOutboundRequests()
		processInboundRequests()
	end)
end

return ServerProcess