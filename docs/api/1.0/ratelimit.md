# Rate Limit <Badge type="tip" text="feature" />

Ratelimit is one of most useful feature.

( Configured on Server only and For Client )

## `Setup`

When creating an event on the server, you can add a second argument (optional, as rate limiting is enabled by default) as a `rateLimit` table to limit the number of times the event can be called and set the interval for resetting the counter on the client side.

::: code-group
```lua [Server]
-- Server
-- Let's make the event have ratelimit with max 50 entrance for 2 seconds.
local Remote = Warp.Server("Remote1", {
	rateLimit = {
		maxEntrance = 50, -- maximum 50 fires. (default is 100)
		interval = 2, -- 2 seconds (default is 1)
	}
})
-- Now the Event RateLimit is configured, and ready to use.
-- No need anything to adds on client side.
```

```lua [Client]
-- Client
local Remote = Warp.Client("Remote1") -- Yields, retreive rateLimit configuration.
-- The Event will automatic it self for retreiving the rate limit configuration from the server.
```
:::

## `Handling Spammers`

If a player exceeds the rate limit, you can optionally listen to `.OnSpamSignal` to detect spamming behavior and react accordingly — such as kicking the player or logging an event.

::: code-group
```lua [Example]
-- Server
local Spammer = Wrap.OnSpamSignal:Wait() -- this return Player instance
Spammer:Kick("Stop spamming our remote event!")
-- Optionally log the spam attempt or notify admins
```
:::