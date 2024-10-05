function widget:GetInfo()
    return {
        name    = "Rocketeer Micro",
        desc    = "Micro has never been easier when a computer does it for you.",
        author  = "TheFortex",
        date    = "2024",
        license = "GNU GPL, v2 or later",
        layer   = 0,
        enabled = true --  loaded by default?
    }
end

--[Configs]:

local dodge_distance = 5
local maxSteps = 100

--[Caching Functions]:

local spGetUnitDefID = Spring.GetUnitDefID
local spGetUnitPosition = Spring.GetUnitPosition
local spGetUnitVelocity = Spring.GetUnitVelocity
local spGetUnitCommands = Spring.GetUnitCommands
local spGetUnitsInSphere = Spring.GetUnitsInSphere

local spGiveOrderToUnit = Spring.GiveOrderToUnit

local spGetProjectileDefID = Spring.GetProjectileDefID
local spGetProjectilePosition = Spring.GetProjectilePosition
local spGetProjectileVelocity = Spring.GetProjectileVelocity
local spGetProjectileTarget = Spring.GetProjectileTarget

local print = Spring.Echo

--[Declarations]:

local myTeam = Spring.GetMyTeamID()

--[Vector class]:

local Vector3 = {}
function Vector3.__index(self, key)
	if key == "x" or key == "y" or key == "z" then
		return self.__protected[key]
	elseif key == "Magnitude" then
		self.__protected.Magnitude = self.__protected.Magnitude or math.sqrt(self.x^2 + self.y^2 + self.z^2)
		return self.__protected.Magnitude
	elseif key == "Unit" then
		self.__protected.Unit = self.__protected.Unit or Vector3.new(self.x / self.Magnitude, self.y / self.Magnitude, self.z / self.Magnitude)
		return self.__protected.Unit
	else
		return Vector3[key]
	end
end

function Vector3.__newindex(self, key, value)
	if key == "x" or key == "y" or key == "z" then
		self.__protected[key] = value
		self.__protected.Magnitude = nil
		self.__protected.Unit = nil
	elseif key == "Magnitude" then
		local unit = self.Unit
		self.__protected.x = unit.x * value
		self.__protected.y = unit.y * value
		self.__protected.z = unit.z * value
		self.__protected.Magnitude = value
	elseif key == "Unit" then
		local magnitude = self.Magnitude
		self.__protected.x = value.x * magnitude
		self.__protected.y = value.y * magnitude
		self.__protected.z = value.z * magnitude
		self.__protected.Unit = value
	else
		rawset(self, key, value)
	end
end

function Vector3.new(x, y, z)
	local self = setmetatable({}, Vector3)
	self.__protected = {x=x,y=y,z=z}
	return self
end

function Vector3:__add(other)
	if type(other) == "number" then
		self = self.__protected
		return Vector3.new(self.x + other, self.y + other, self.z + other)
	else
		self, other = self.__protected, other.__protected
		return Vector3.new(self.x + other.x, self.y + other.y, self.z + other.z)
	end
end

function Vector3:__sub(other)
	if type(other) == "number" then
		self = self.__protected
		return Vector3.new(self.x - other, self.y - other, self.z - other)
	else
		self, other = self.__protected, other.__protected
		return Vector3.new(self.x - other.x, self.y - other.y, self.z - other.z)
	end
end

function Vector3:__mul(other)
	if type(other) == "number" then
		self = self.__protected
		return Vector3.new(self.x * other, self.y * other, self.z * other)
	else
		self, other = self.__protected, other.__protected
		return self.x * other.x + self.y * other.y + self.z * other.z
	end
end

function Vector3:__tostring()
	self = self.__protected
	return string.format("Vector3(%f, %f, %f)", self.x, self.y, self.z)
end

function Vector3:Cross(other)
	self, other = self.__protected, other.__protected
	return Vector3.new(self.y * other.z - self.z * other.y, self.z * other.x - self.x * other.z, self.x * other.y - self.y * other.x)
end

--[Projectile Tracking]:

local armRocket = WeaponDefNames["armrock_arm_bot_rocket"].id
local corRocket = WeaponDefNames["corstorm_cor_bot_rocket"].id

local rocketZones = {}

local function GetRocketZone(projID, weapDef)
	local pStart = Vector3.new(spGetProjectilePosition(projID))
	local pEnd

	local targetTypeInt, target = spGetProjectileTarget(projID)
	if targetTypeInt == string.byte('g') then
		pEnd = Vector3.new(target[1], target[2], target[3])
	else
		local v = Vector3.new(spGetProjectileVelocity(projID))
		pEnd = pStart + v.Unit * weapDef.range * 1.5
	end

	local u = pEnd - pStart
	local width = 20
	local right = u:Cross(Vector3.new(0,1,0)).Unit

	local p1 = pEnd + right * (width/2)
	local p2 = pEnd - right * (width/2)
	local p3 = pStart - right * (width/2)
	local p4 = pStart + right * (width/2)

	return p1, p2, p3, p4
end

local function IsPointInRect(point, rec1, rec2, rec3, rec4)
	local function IsLeft(p1, p2, p3)
		return (p2.x - p1.x) * (p3.z - p1.z) - (p3.x - p1.x) * (p2.z - p1.z)
	end

	return IsLeft(rec1, rec2, point) >= 0 and IsLeft(rec2, rec3, point) >= 0 and IsLeft(rec3, rec4, point) >= 0 and IsLeft(rec4, rec1, point) >= 0
end

local function IsCircleIntersectingWithLine(cirPos, cirRadius, line1, line2)
	local a = line1 - line2
	local b = cirPos - line2
	return math.abs(a:Cross(b).Magnitude / a.Magnitude) <= cirRadius
end

local function IsCircleIntersectingWithRect(cirPos, cirRadius, rec1, rec2, rec3, rec4)
	return IsPointInRect(cirPos, rec1, rec2, rec3, rec4) or
	IsCircleIntersectingWithLine(cirPos, cirRadius, rec1, rec2) or
	IsCircleIntersectingWithLine(cirPos, cirRadius, rec2, rec3) or
	IsCircleIntersectingWithLine(cirPos, cirRadius, rec3, rec4) or
	IsCircleIntersectingWithLine(cirPos, cirRadius, rec4, rec1)
end

local function GetRocketZoneIntersectingWithCircle(cirPos, cirRadius)
	for _, zone in pairs(rocketZones) do
		if IsCircleIntersectingWithRect(cirPos, cirRadius, zone[1], zone[2], zone[3], zone[4]) then
			return zone
		end
	end
end

local function Dodge(unitID)
	local radius = UnitDefs[spGetUnitDefID(unitID)].collisionVolume.boundingRadius
	local cmd = spGetUnitCommands(unitID, 1)[1]
	local dodgePos

	if cmd and cmd.options.alt then
		if cmd.id == CMD.MOVE and GetRocketZoneIntersectingWithCircle(Vector3.new(cmd.params[1], cmd.params[2], cmd.params[3]), radius) then
			dodgePos = Vector3.new(cmd.params[1], cmd.params[2], cmd.params[3])
		else
			return
		end
	else
		dodgePos = Vector3.new(spGetUnitPosition(unitID))
	end

	local dodging = false
	for i = 1, maxSteps do
		-- print("Dodge step", i)
		local zone = GetRocketZoneIntersectingWithCircle(dodgePos, radius)
		if zone then
			dodging = true
			-- Move the dodgePos to the right of the zone by `radius`
			local zoneRight = (zone[1] - zone[2]).Unit
			dodgePos = dodgePos + (zoneRight * radius * (math.random() <0.5 and 1 or -1))
		else
			break
		end
	end

	if dodging then
		local prevCmds = spGetUnitCommands(unitID, -1)
		spGiveOrderToUnit(unitID, CMD.MOVE, {dodgePos.x, dodgePos.y, dodgePos.z}, {"alt"})
		for _, cmd in pairs(prevCmds) do
			table.insert(cmd.options, "shift")
			spGiveOrderToUnit(unitID, cmd.id, cmd.params, cmd.options)
		end
	end
end

function widget:GameFrame(frame) -- Indentation hell incoming
	if frame % 10 ~= 0 then return end
	local allProjectiles = Spring.GetProjectilesInRectangle(0, 0, Game.mapSizeX, Game.mapSizeZ, false, true)

	local newRocketZones = {}

	for _, projID in pairs(allProjectiles) do
		local projDef = spGetProjectileDefID(projID)
		if projDef == armRocket or projDef == corRocket then
			if not rocketZones[projID] then
				newRocketZones[projID] = {GetRocketZone(projID, WeaponDefs[projDef])}
			else
				newRocketZones[projID] = rocketZones[projID]
			end
		end
	end

	rocketZones = newRocketZones

	local myUnits = spGetUnitsInSphere(0, 0, 0, 999999, myTeam)
	for _, unitID in pairs(myUnits) do
		local unitDefID = spGetUnitDefID(unitID)
		if not UnitDefs[unitDefID].isBuilding then
			Dodge(unitID)
		end
	end
end

--[Widget Functions]:

function widget:Initialize()
    if Spring.GetSpectatingState() then
        widgetHandler:RemoveWidget(self)
        do return end
    end
end

function widget:PlayerChanged(playerID)
    if Spring.GetSpectatingState() then
        widgetHandler:RemoveWidget(self)
    end
end
