-- Warp Library (orginal by @Eternity_Devs, modified by @ttam-dev)
-- version 1.0.14
--!strict
--!optimize 2
local Index = require(script.Index)

return {
	Server = Index.Server,
	Client = Index.Client,
	fromServerArray = Index.fromServerArray,
	fromClientArray = Index.fromClientArray,
	
	OnSpamSignal = Index.OnSpamSignal,

	Signal = Index.Signal,
	fromSignalArray = Index.fromSignalArray,

	buffer = Index.buffer,
}