local Display = {}

function Display.Number(value, decimals)
	local number = tonumber(value)
	if not number then
		return "-"
	end
	return string.format("%." .. tostring(decimals or 0) .. "f", number)
end

function Display.Integer(value)
	local number = tonumber(value)
	if not number then
		return nil
	end
	return string.format("%d", math.floor(number))
end

local function TrimTrailingZeros(text)
	text = string.gsub(text, "(%..-)0+$", "%1")
	return string.gsub(text, "%.$", "")
end

local function RoundNumber(value)
	if value >= 0 then
		return math.floor(value + 0.5)
	end
	return math.ceil(value - 0.5)
end

function Display.RoundedNumber(value, decimals)
	local places = math.max(0, tonumber(decimals) or 0)
	return TrimTrailingZeros(string.format("%." .. tostring(places) .. "f", value))
end

function Display.DecimalPlacesForStep(step)
	local text = tostring(step)
	if string.find(text, "[eE]") then
		text = string.format("%.10f", tonumber(step) or 0)
	end
	text = TrimTrailingZeros(text)
	local dotIndex = string.find(text, ".", 1, true)
	if not dotIndex then
		return 0
	end
	return math.max(0, #text - dotIndex)
end

function Display.RoundToStep(value, step)
	local numericStep = tonumber(step)
	if not numericStep or numericStep <= 0 then
		return value
	end
	return RoundNumber(value / numericStep) * numericStep
end

function Display.CleanFloat(value)
	local number = tonumber(value)
	if not number then
		return tostring(value or "")
	end
	local text = tostring(value)
	if not string.find(text, "[%.eE]") then
		return text
	end
	for decimals = 0, 6 do
		local factor = 10 ^ decimals
		local rounded = RoundNumber(number * factor) / factor
		if math.abs(number - rounded) < 0.000001 then
			return Display.RoundedNumber(rounded, decimals)
		end
	end
	return text
end

function Display.Percent(value)
	local number = tonumber(value)
	if not number then
		return nil
	end
	return Display.RoundedNumber(number * 100, 1) .. "%"
end

function Display.Duration(milliseconds)
	local value = tonumber(milliseconds)
	if not value then
		return nil
	end
	if value < 1000 then
		return tostring(math.floor(value + 0.5)) .. " ms"
	end
	return Display.RoundedNumber(value / 1000, 3) .. " s"
end

function Display.ByteSize(bytes)
	local value = tonumber(bytes)
	if not value then
		return nil
	end
	if value < 1024 then
		return tostring(math.floor(value)) .. " B"
	end
	if value < 1024 * 1024 then
		return Display.RoundedNumber(value / 1024, 1) .. " KiB"
	end
	return Display.RoundedNumber(value / (1024 * 1024), 1) .. " MiB"
end

local DAYS_BEFORE_MONTH = {0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334}
local DAYS_IN_MONTH = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}

local function IsLeapYear(year)
	return year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0)
end

local function DaysBeforeYear(year)
	local previousYear = year - 1
	return (previousYear * 365)
		+ math.floor(previousYear / 4)
		- math.floor(previousYear / 100)
		+ math.floor(previousYear / 400)
end

local EPOCH_DAYS = DaysBeforeYear(1970)

local function UtcEpochSeconds(year, month, day, hour, minute, second)
	if month < 1 or month > 12 then
		return nil
	end
	if hour < 0 or hour > 23 or minute < 0 or minute > 59 or second < 0 or second > 60 then
		return nil
	end
	local daysInMonth = DAYS_IN_MONTH[month]
	if month == 2 and IsLeapYear(year) then
		daysInMonth = 29
	end
	if day < 1 or day > daysInMonth then
		return nil
	end
	local days = DaysBeforeYear(year) - EPOCH_DAYS + DAYS_BEFORE_MONTH[month] + day - 1
	if month > 2 and IsLeapYear(year) then
		days = days + 1
	end
	return ((((days * 24) + hour) * 60) + minute) * 60 + second
end

function Display.ParseUtcTimestamp(value)
	local year, month, day, hour, minute, second = string.match(
		tostring(value or ""),
		"^(%d%d%d%d)%-(%d%d)%-(%d%d)[Tt ](%d%d):(%d%d):(%d%d)"
	)
	if not year then
		return nil
	end
	return UtcEpochSeconds(
		tonumber(year),
		tonumber(month),
		tonumber(day),
		tonumber(hour),
		tonumber(minute),
		tonumber(second)
	)
end

local function Plural(value, unit)
	if value == 1 then
		return "1 " .. unit
	end
	return tostring(value) .. " " .. unit .. "s"
end

function Display.AgeText(ageSeconds)
	local seconds = tonumber(ageSeconds)
	if not seconds or seconds < 0 then
		return nil
	end
	local totalMinutes = math.floor(seconds / 60)
	if totalMinutes < 1 then
		return "less than 1 minute ago"
	end
	local days = math.floor(totalMinutes / (24 * 60))
	local remainingMinutes = totalMinutes - days * 24 * 60
	local hours = math.floor(remainingMinutes / 60)
	local minutes = remainingMinutes - hours * 60
	local parts = {}
	for _, part in ipairs({{days, "day"}, {hours, "hour"}, {minutes, "minute"}}) do
		if part[1] > 0 and #parts < 2 then
			parts[#parts + 1] = Plural(part[1], part[2])
		end
	end
	return table.concat(parts, " ") .. " ago"
end

return Display
