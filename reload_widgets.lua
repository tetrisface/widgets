function widget:GetInfo()
	return {
		name = 'Reload Widgets',
		desc = '',
		author = 'tetrisface',
		version = '',
		date = 'jan, 2024',
		license = '',
		layer = -99990,
		enabled = false,
	}
end

VFS.Include('luaui/Widgets/.noload/misc/helpers.lua')
VFS.Include('luaui/Headers/keysym.h.lua')

function widget:KeyPress(key, mods, isRepeat)
	-- log('key', key, mods)
	if key == KEYSYMS.R and mods['ctrl'] then
		Spring.SendCommands('disablewidget Reload Widgets')
		Spring.SendCommands('enablewidget Reload Widgets')
		-- Spring.SendCommands("disablewidget Snap Mouse")
		-- Spring.SendCommands("enablewidget Snap Mouse")
		-- Spring.SendCommands("disablewidget GUI PVE Wave Info")
		-- Spring.SendCommands("enablewidget GUI PVE Wave Info")
		-- Spring.SendCommands('disablewidget Shield Ground Rings')
		-- Spring.SendCommands('enablewidget Shield Ground Rings')
		-- Spring.SendCommands('disablewidget Shield Ground Rings')
		-- Spring.SendCommands('enablewidget Shield Ground Rings')
		-- Spring.SendCommands('disablewidget Straight Lines')
		-- Spring.SendCommands('enablewidget Straight Lines')
		-- Spring.SendCommands("disablewidget Build Shortcuts")
		-- Spring.SendCommands("enablewidget Build Shortcuts")
		-- Spring.SendCommands('disablewidget Auto Unit Settings')
		-- Spring.SendCommands('enablewidget Auto Unit Settings')
		-- Spring.SendCommands('disablewidget eco cons')
		-- Spring.SendCommands('enablewidget eco cons')
		-- Spring.SendCommands('disablewidget Base Painter')
		-- Spring.SendCommands('enablewidget Base Painter')
		-- Spring.SendCommands('disablewidget Commands')
		-- Spring.SendCommands('enablewidget Commands')
		Spring.SendCommands('disablewidget Building Grid GL4')
		Spring.SendCommands('enablewidget Building Grid GL4')
		-- Spring.SendCommands('disablewidget Raptor Nuke Warning')
		-- Spring.SendCommands('enablewidget Raptor Nuke Warning')
		-- Spring.SendCommands("disablewidget Dont Stand in Fire")
		-- Spring.SendCommands("enablewidget Dont Stand in Fire")
		-- Spring.SendCommands("disablewidget CMD Build Spacing")
		-- Spring.SendCommands("enablewidget CMD Build Spacing")
		-- Spring.SendCommands("disablewidget History")
		-- Spring.SendCommands("enablewidget History")
		-- Spring.SendCommands("disablewidget CMD target time spread")
		-- Spring.SendCommands("enablewidget CMD target time spread")
		-- Spring.SendCommands('disablewidget Raptor Stats Panel With Eco Attraction')
		-- Spring.SendCommands('enablewidget Raptor Stats Panel With Eco Attraction')
		return false
	end
	-- if key == 113 and mods['ctrl'] then
	--   local cmds = Spring.GetUnitCommands(17574, 5)
	--   log('cmds', table.echo(cmds))
	-- end
end

-- function getReclaimableFeature(x , z, radius)
--   local wrecksInRange = GetFeaturesInCylinder(x, z, radius)

--   if #wrecksInRange == 0 then
--     return
--   end

--   -- for i=1, #wrecksInRange do
--   --   local metal, _, energy = GetFeatureResources(featureId)
--   --   if metal + energy == 0 then
--   --     goto continue
--   --   end
--   --   local featureId = wrecksInRange[i]
--   --   local featureId = wrecksInRange[i]
--   --   ::continue::
--   -- end
--   local featureId = wrecksInRange[1]
--   local metal, _, energy = GetFeatureResources(featureId)
--   -- log('feature metal ' .. metal, ' energy ' .. energy)
--   return featureId
-- end

-- function widget:KeyPress(key, mods, isRepeat)
--   log(key .. " "..table.tostring(mods))

--   if key ~= 306 and key ~= 9 then
--     return
--   end

--   local mouse_x, mouse_y = GetMouseState ( )
--   -- local mouse_x, mouse_y = GetMouseStartPosition(0)
--   -- local wrecksInRange = GetFeaturesInCylinder(mpx, mpz, builderDef.buildDistance)
--   local desc, args = TraceScreenRay(mouse_x, mouse_y, true)
--   if nil == desc then return end -- off map
--   local x = args[1]
--   local y = args[2]
--   local z = args[3]
--   log('x ' .. x .. ' z ' .. z)

--   local selectedUnits = GetSelectedUnits()
--   local unitId = 26618

--   -- log(table.tostring(selectedUnits))

--   local featureId = getReclaimableFeature(x, z, 123)

--   if not featureId then
--     return
--   end

--   log('featureId ' .. (featureId or ''))

--   local queue = GetUnitCommands(unitId, 1)

--   -- already reclaiming
--   if #queue > 0 and queue[1].id == 90 then
--     return
--   end

--   GiveOrderToUnit(unitId, CMD.INSERT, {0, CMD.RECLAIM, CMD.OPT_SHIFT, Game.maxUnits+featureId}, {'alt'})
--   -- local selectedUnits0 = GetSelectedUnits()

--   -- local camera0 = GetCameraPosition()

--   -- local visibleUnitsArr = GetVisibleUnits(myTeamId, nil, true)
--   -- local visibleUnits = {}
--   -- for i=1, #visibleUnitsArr do
--   --   local unitId = visibleUnitsArr[i]
--   --   visibleUnits[unitId] = GetUnitViewPosition(unitId)
--   -- end

--   -- boundaries =

-- end

-- function getPositionBoundaries(points)
--   local xMin = math.huge
--   local zMin = math.huge
--   local xMax = -math.huge
--   local zMax = -math.huge
--   for i = 1, #points  do
--     local point = points[i]
--     xMin = xMin < point.x and xMin or point.x
--     xMax = xMax > point.x and xMax or point.x
--     zMin = zMin < point.z and zMin or point.z
--     zMax = zMax > point.z and zMax or point.z
--   end
--   return xMin, xMax, yMin, yMax
-- end
