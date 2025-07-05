--!strict
--!optimize 2
local ClientProcess = {}

local RunService = game:GetService("RunService")
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

local clientRatelimit: Type.StoredRatelimit = {}
local clientQueue: Type.QueueMap = {}
local unreliableClientQueue: Type.QueueMap = {}
local clientCallback: Type.CallbackMap = {}
local clientRequestQueue: Type.QueueMap = {}
local registeredIdentifier: { [string]: boolean } = {}

local queueInRequest: {
	[number]: {
		[string]: { any },
	},
} = {}
local queueOutRequest: {
	[number]: {
		[string]: { any },
	},
} = {}

queueInRequest[1] = {}
queueInRequest[2] = {}
queueOutRequest[1] = {}
queueOutRequest[2] = {}

local ReliableEvent = Event.Reliable
local UnreliableEvent = Event.Unreliable
local RequestEvent = Event.Request

local function processUnreliable()
	for Identifier: string, data: any in unreliableClientQueue do
		if #data > 0 then
			if clientRatelimit[Identifier](#data) then
				for _, unpacked in data do
					UnreliableEvent:FireServer(Buffer.revert(Identifier), Buffer.write(unpacked))
				end
			end

			recycle(unreliableClientQueue[Identifier])
		end
	end
end

local function processReliable()
	for Identifier: string, data: any in clientQueue do
		if #data > 0 then
			if clientRatelimit[Identifier](#data) then
				for _, unpacked in data do
					ReliableEvent:FireServer(Buffer.revert(Identifier), Buffer.write(unpacked))
				end
			end

			recycle(clientQueue[Identifier])
		end
	end
end

local function processOutboundRequests()
	for i = 1, 2 do
		local queue = queueOutRequest[i]
		local action = i == 1 and "\1" or "\0"
		for Identifier: string, data in queue do
			if #data > 0 then
				RequestEvent:FireServer(Buffer.revert(Identifier), action, data)
				recycle(queue[Identifier])
			end
		end
	end
end

local function processInboundRequests()
	for Identifier: string in registeredIdentifier do
		if clientRequestQueue[Identifier] then
			for _, requestData in clientRequestQueue[Identifier] do
				if not requestData[3] then
					continue
				end
				ensure(queueOutRequest[1], Identifier)
				table.insert(queueOutRequest[1][Identifier], { requestData[1], requestData[3] })
				table.remove(requestData, 3) -- remove the data from the request queue
			end
		end

		-- Unreliable & Reliable
		local callback = clientCallback[Identifier] or nil
		if not callback or typeof(callback) ~= "function" then
			continue
		end

		-- Return Invoke
		if queueInRequest[1][Identifier] then --> {}
			for _, packetDatas: any in queueInRequest[1][Identifier] do
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
							local ok, result = pcall(fn, table.unpack(packetData2))
							if ok then
								result = { result }
								ensure(queueOutRequest[2], Identifier)
								table.insert(queueOutRequest[2][Identifier], { packetData1, result })
							else
								Assert(false, `Error in callback for {Identifier}: {result}`, 2)
							end
						end)
					end
				end
			end

			recycle(queueInRequest[1][Identifier])
		end

		-- Call to Invoke
		if queueInRequest[2][Identifier] then
			if clientRequestQueue[Identifier] then
				for _, packetDatas: any in queueInRequest[2][Identifier] do
					for _, packetData in packetDatas do
						if #packetData == 1 then
							continue
						end
						for y = 1, #clientRequestQueue[Identifier] do
							local clientRequest = clientRequestQueue[Identifier][y]
							if not clientRequest then
								continue
							end
							if clientRequest[1] == packetData[1] then
								Spawn(clientRequest[1], table.unpack(packetData[2]))
								table.remove(clientRequestQueue[Identifier], y)
								break
							end
						end
					end
				end
			end

			recycle(queueInRequest[2][Identifier])
		end
	end
end

local function onClientNetworkReceive(Identifier: buffer | string, data: buffer, ref: { any }?)
	if not Identifier or typeof(Identifier) ~= "buffer" or not data or typeof(data) ~= "buffer" then
		return
	end
	Identifier = Buffer.convert(Identifier)
	if typeof(Identifier) ~= "string" then
		return
	end -- ensure it's string
	if not registeredIdentifier[Identifier] then
		return
	end
	local read = Buffer.read(data, ref)
	if not read then
		return
	end
	local callback = clientCallback[Identifier :: string]
	if not callback then
		return
	end
	for _, fn: any in callback do
		Spawn(fn, table.unpack(read))
	end
end

local function onClientRequestReceive(Identifier: any, action: string, data)
	if not Identifier or not data then
		return
	end
	Identifier = Buffer.convert(Identifier)
	if typeof(Identifier) ~= "string" then
		return
	end -- ensure it's string
	if action == "\1" then
		ensure(queueInRequest[1], Identifier)
		table.insert(queueInRequest[1][Identifier], data)
	else
		ensure(queueInRequest[2], Identifier)
		table.insert(queueInRequest[2][Identifier], data)
	end
end

function ClientProcess.insertQueue(Identifier: string, reliable: boolean, ...: any)
	if not reliable then
		ensure(unreliableClientQueue, Identifier)
		table.insert(unreliableClientQueue[Identifier], { ... })
		return
	end
	ensure(clientQueue, Identifier)
	table.insert(clientQueue[Identifier], { ... })
end

function ClientProcess.insertRequest(Identifier: string, timeout: number, ...: any)
	ensure(clientRequestQueue, Identifier)
	local yieldThread: thread, start = coroutine.running(), os.clock()
	local cancel = task.delay(timeout, function()
		task.spawn(yieldThread, nil)
	end)
	table.insert(clientRequestQueue[Identifier], {
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

function ClientProcess.add(Identifier: any, originId: string, _: Type.ClientConf)
	if not registeredIdentifier[Identifier] then
		registeredIdentifier[Identifier] = true

		if not clientRatelimit[Identifier] then
			clientRatelimit[Identifier] = RateLimit.create(originId)
		end

		ensure(clientQueue, Identifier)
		ensure(unreliableClientQueue, Identifier)
		ensure(clientRequestQueue, Identifier)
		ensure(clientCallback, Identifier)
		ensure(queueOutRequest[1], Identifier)
		ensure(queueOutRequest[2], Identifier)
		ensure(queueInRequest[1], Identifier)
		ensure(queueInRequest[2], Identifier)
	end
end

function ClientProcess.remove(Identifier: string)
	if not registeredIdentifier[Identifier] then
		return
	end
	registeredIdentifier[Identifier] = nil

	clear(clientQueue, Identifier)
	clear(unreliableClientQueue, Identifier)
	clear(clientRequestQueue, Identifier)
	clear(clientCallback, Identifier)
	clear(clientRatelimit, Identifier)
	clear(queueOutRequest[1], Identifier)
	clear(queueOutRequest[2], Identifier)
	clear(queueInRequest[1], Identifier)
	clear(queueInRequest[2], Identifier)
end

function ClientProcess.addCallback(Identifier: string, key: string, callback)
	clientCallback[Identifier][key] = callback
end

function ClientProcess.removeCallback(Identifier: string, key: string)
	clientCallback[Identifier][key] = nil
end

function ClientProcess.start()
	-- Ensure the events are connected
	ReliableEvent.OnClientEvent:Connect(onClientNetworkReceive)
	UnreliableEvent.OnClientEvent:Connect(onClientNetworkReceive)
	RequestEvent.OnClientEvent:Connect(onClientRequestReceive)

	-- Set up the RunService to process the queues
	debug.setmemorycategory("Warp.ClientProcess")
	RunService.PostSimulation:Connect(function()
		processUnreliable()
		processReliable()
		processOutboundRequests()
		processInboundRequests()
	end)
end

return ClientProcess