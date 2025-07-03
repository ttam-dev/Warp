--!strict
--!native
--!optimize 2
local Buffer = {}
Buffer.__index = Buffer

local Dedicated = require(script.Dedicated)

-- Constants for type markers
local TYPE_NIL = 0
local TYPE_INSTANCE = -1
local TYPE_ARRAY = -2
local TYPE_DICT = -3
local TYPE_ENUM_ITEM = -4
local TYPE_BRICKCOLOR = -5
local TYPE_ENUM = -6
local TYPE_U8 = 1
local TYPE_I16 = 2
local TYPE_I32 = 3
local TYPE_F64 = 4
local TYPE_BOOL = 5
local TYPE_STRING_U8 = 6
local TYPE_STRING_U16 = 7
local TYPE_STRING_I32 = 8
local TYPE_VECTOR3 = 9
local TYPE_VECTOR2 = 10
local TYPE_CFRAME = 11
local TYPE_COLOR3 = 12

local tostring = buffer.tostring
local fromstring = buffer.fromstring
local readu8 = buffer.readu8
local readi8 = buffer.readi8
local readu16 = buffer.readu16
local readi16 = buffer.readi16
local readi32 = buffer.readi32
local readf32 = buffer.readf32
local readf64 = buffer.readf64
local readstring = buffer.readstring
local len = buffer.len

local function readValue(b: buffer, position: number, ref: { any }?): (any, number)
	local typeByte = readi8(b, position)
	position += 1
	if typeByte == TYPE_NIL then
		return nil, position
	elseif typeByte == TYPE_INSTANCE then
		if not ref or #ref == 0 then
			return nil, position + 1
		end
		local value = ref[readu8(b, position)]
		return typeof(value) == "Instance" and value or nil, position + 1
	elseif typeByte == TYPE_ARRAY then
		local length = readu16(b, position)
		position += 2
		local array = {}
		for _ = 1, length do
			local value
			value, position = readValue(b, position, ref)
			table.insert(array, value)
		end
		return array, position
	elseif typeByte == TYPE_DICT then
		local length = readu16(b, position)
		position += 2
		local dict = {}
		for _ = 1, length do
			local key, value
			key, position = readValue(b, position, ref)
			value, position = readValue(b, position, ref)
			dict[key] = value
		end
		return dict, position
	elseif typeByte == TYPE_ENUM_ITEM then
		local length = readi8(b, position)
		local enumName = readstring(b, position + 1, length)
		local value = readu8(b, position + 1 + length)
		return Enum[enumName]:FromValue(value), position + 2 + length
	elseif typeByte == TYPE_BRICKCOLOR then
		return BrickColor.new(readi16(b, position)), position + 2
	elseif typeByte == TYPE_ENUM then
		local length = readi8(b, position)
		local enumName = readstring(b, position + 1, length)
		return Enum[enumName], position + 1 + length
	elseif typeByte == TYPE_U8 then
		return readu8(b, position), position + 1
	elseif typeByte == TYPE_I16 then
		return readi16(b, position), position + 2
	elseif typeByte == TYPE_I32 then
		return readi32(b, position), position + 4
	elseif typeByte == TYPE_F64 then
		return readf64(b, position), position + 8
	elseif typeByte == TYPE_BOOL then
		return readu8(b, position) == 1, position + 1
	elseif typeByte == TYPE_STRING_U8 then
		local length = readu8(b, position)
		local value = readstring(b, position + 1, length)
		return value, position + length + 1
	elseif typeByte == TYPE_STRING_U16 then
		local length = readu16(b, position)
		local value = readstring(b, position + 2, length)
		return value, position + length + 2
	elseif typeByte == TYPE_STRING_I32 then
		local length = readi32(b, position)
		local value = readstring(b, position + 4, length)
		return value, position + length + 4
	elseif typeByte == TYPE_VECTOR3 then
		local x = readf32(b, position)
		local y = readf32(b, position + 4)
		local z = readf32(b, position + 8)
		return Vector3.new(x, y, z), position + 12
	elseif typeByte == TYPE_VECTOR2 then
		local x = readf32(b, position)
		local y = readf32(b, position + 4)
		return Vector2.new(x, y), position + 8
	elseif typeByte == TYPE_CFRAME then
		local components = {}
		for i = 1, 12 do
			components[i] = readf32(b, position + (i - 1) * 4)
		end
		return CFrame.new(unpack(components)), position + 48
	elseif typeByte == TYPE_COLOR3 then
		local r = readu8(b, position)
		local g = readu8(b, position + 1)
		local bVal = readu8(b, position + 2)
		return Color3.fromRGB(r, g, bVal), position + 3
	end
	error(`Unsupported type marker: {typeByte} at position {position}`)
end

function Buffer.new(): Dedicated.DedicatedType
	return Dedicated()
end

function Buffer.convert(b: buffer): string
	return tostring(b)
end

function Buffer.revert(s: string): buffer
	return fromstring(s)
end

function Buffer.write(data: { any }): (buffer, (any)?)
	local newBuffer = Dedicated()
	newBuffer:pack(data)
	return newBuffer:buildAndRemove()
end

function Buffer.read(b: buffer, ref: { any }?): any?
	local position = 0
	local result = {}
	while position < len(b) do
		local value
		value, position = readValue(b, position, ref)
		table.insert(result, value)
	end
	return table.unpack(result)
end

return Buffer :: typeof(Buffer)