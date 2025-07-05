--!strict
--!optimize 2
return function(condition: (any), errorMessage: string, level: number): ()
	--[[
		Asserts that a condition is true, otherwise logs an error or raises an error.
		Parameters:
			condition: The condition to check.
			errorMessage: The message to log or raise if the condition is false.
			level: The level of the error (1 for warning, 2 for error).
	]]

	local scriptName = debug.info(2, "s").Name
	if not (condition) then 
		if level == 1 then
			warn(`[Warp.{scriptName}]: {errorMessage}`)
		elseif level == 2 then
			error(`[Warp.{scriptName}]: {errorMessage}`, 2)
		end
	end
end