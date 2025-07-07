# Server <Badge type="tip" text="event" />

For Server-sided

## `.Server` <Badge type="warning" text="yield" />

Create new Warp event.

::: code-group
```lua [Variable]
(
	Identifier: string,
	rateLimit: {
		maxEntrance: number?,
		interval: number?,
	}?
)
```

```lua [Example]
local Remote = Warp.Server("Remote")
```
:::

## `.fromServerArray` <Badge type="warning" text="yield" />

Create new Warp events with array.

::: code-group
```lua [Variable]
(
	{ any }
)
```

```lua [Example]
local Events = Warp.fromServerArray({
	["Remote1"] = {
		rateLimit = {
			maxEntrance: 50,
			interval: 1,
		}
	}, -- with rateLimit configuration
	"Remote2", -- without rateLimit configuration
	["Remote3"] = {
		rateLimit = {
			maxEntrance: 10,
		}
	}, -- with rateLimit configuration
})

-- Usage
Events.Remote1:Connect(function(player, ...) end)
Events.Remote2:Connect(function(player, ...) end)
Events.Remote3:Connect(function(player, ...) end)
```
:::
## `:Connect`

Connect event to receive incoming from client way.

::: code-group
```lua [Variable]
(
	player: Player,
	callback: (...any) -> ()
): string
```

```lua [Example]
Remote:Connect(function(player, ...)
	print(player, ...)
end)
```
:::

## `:Once`

This function likely `:Connect` but it disconnect the event once it fired.

::: code-group
```lua [Variable]
(
	player: Player,
	callback: (...any) -> ()
)
```

```lua [Example]
Remote:Once(function(player, ...)
	print(player, ...)
end)
```
:::

## `:Disconnect`

Disconnect the event connection.

::: code-group
```lua [Variable]
(
	key: string
): boolean
```

```lua [Example]
local connection = Remote:Connect(function(player, ...) end) -- store the key

Remote:Disconnect(connection)
```
:::

## `:DisconnectAll`

Disconnect All the event connection.

```lua [Example]
Remote:DisconnectAll()
```

## `:Fire`

Fire the event to a client.

::: code-group
```lua [Variable]
(
	reliable: boolean,
    player: Player,
	...: any
)
```

```lua [Example]
Remote:Fire(true, player, "Hello World!")
```
:::

## `:FireAll` <Badge type="tip" text="Server Only" />

Fire the event to all clients.

::: code-group
```lua [Variable]
(
	reliable: boolean,
	...: any
)
```

```lua [Example]
Remote:FireAll(true, "Hello World!")
```
:::

## `:FireAllExcept` <Badge type="tip" text="Server Only" />

Fire the event to all clients but except some players.

::: code-group
```lua [Variable]
(
	reliable: boolean,
	except: { Player },
	...: any
)
```

```lua [Example]
Remote:FireAllExcept(true, { Players.Player1, Players.Player2 }, "Hello World!") -- this will sent to all players except { Players.Player1, Players.Player2 }.
```
:::

## `:FireAllIn` <Badge type="tip" text="Server Only" />

Fire the event to all players within a certain range from a position, optionally excluding some players.

::: code-group
```lua [Variable]
(
	reliable: boolean,
	range: number,
	from: Vector3,
	data: { any },
	except: { Player }?
)
```

```lua [Example]
Remote:FireAllIn(true, 100, Vector3.new(0, 5, 0), { "Hello World!", 123 }, { Players.Player1, Players.Player2 }) -- sends to all players within 100 studs of (0,5,0) except Players.Player1 and Players.Player2.
```
:::

## `:Invoke` <Badge type="warning" text="yield" />

Semiliar to `:InvokeClient`,  but it have timeout system that not exists on `RemoteFunction.InvokeClient`.

::: code-group
```lua [Variable]
(
	timeout: number,
    player: Player,
	...: any
) -> (...any)
```

```lua [Example]
local Request = Remote:Invoke(2, player, "Hello World!")
```
:::

::: warning
This function is yielded, once it timeout it will return nil.
:::

## `:Wait` <Badge type="warning" text="yield" />

Wait the event being triggered.

```lua
Remote:Wait() -- :Wait return number value
```

::: warning
This function is yielded, Invoke might also ping this one and also causing error.
:::

## `:Destroy`

Disconnect all connection of event and remove the event from Warp.

```lua
Remote:Destroy()
```