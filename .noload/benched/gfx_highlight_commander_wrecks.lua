function widget:GetInfo()
  return {
    name = "Highlight Commander Wrecks",
    desc = "Show a vertical beam on each dead commander that can be resurrected",
    author = "citrine",
    date = "2024",
    license = "GNU GPL, v2 or later",
    version = 5,
    layer = 0,
    enabled = false
  }
end

-- configuration
-- ==================

local config = {
  useTeamColor = false,
}

local CYLINDER_SECTIONS = 16
local CYLINDER_RADIUS = 5
local CYLINDER_HEIGHT = 1500

local DEFAULT_COLOR = { 0.9, 0.5, 1, 0.7 }
local DEFAULT_OPACITY = 1.0

-- engine call optimizations
-- =========================

local SpringGetAllFeatures = Spring.GetAllFeatures
local SpringGetFeatureResurrect = Spring.GetFeatureResurrect
local SpringGetFeatureResources = Spring.GetFeatureResources
local SpringGetFeaturePosition = Spring.GetFeaturePosition
local SpringGetFeatureTeam = Spring.GetFeatureTeam
local SpringGetTeamColor = Spring.GetTeamColor
local SpringGetSpectatingState = Spring.GetSpectatingState
local SpringGetMapDrawMode = Spring.GetMapDrawMode

-- util
-- ====

local function map(list, func)
  local result = {}
  for i, v in ipairs(list) do
    result[i] = func(v, i)
  end
  return result
end

-- GL4
-- ===

local includeDir = "LuaUI/Widgets/Include/"
local LuaShader = VFS.Include(includeDir .. "LuaShader.lua")
VFS.Include(includeDir .. "instancevbotable.lua")

local vsSrc = [[
#version 420
#line 10000

//__ENGINEUNIFORMBUFFERDEFS__

layout (location = 0) in vec3 local_pos;

layout (location = 1) in vec3 world_pos;
layout (location = 2) in float radius;
layout (location = 3) in float height;
layout (location = 4) in vec4 color;

out DataVS {
  vec4 vertex_color;
  float local_y;
  float cameraDistance;
};

#line 15000
void main() {
	cameraDistance = length(world_pos.xyz - cameraViewInv[3].xyz);

	float effectiveRadius = radius * clamp(cameraDistance / 4500, 1.0, 2.5);

  vec2 result_pos_xz = local_pos.xz * effectiveRadius + world_pos.xz;
  vec3 result_pos = vec3(result_pos_xz.x, world_pos.y + local_pos.y * height, result_pos_xz.y);

  gl_Position = cameraViewProj * vec4(result_pos, 1.0);

  vertex_color = color;
  local_y = local_pos.y;
}
]]

local fsSrc = [[
#version 420
#line 20000

in DataVS {
  vec4 vertex_color;
  float local_y;
  float cameraDistance;
};

out vec4 output_color;

#line 25000
void main() {
  output_color.rgba = vec4(
    vertex_color.rgb,
    clamp(
      vertex_color.a
       * (1 - sqrt(local_y)) // more opacity near the ground
       * clamp(cameraDistance / 4500, 0.2, 1.2), // more opacity from far away
      0.0,
      1.0
    )
  );
}
]]

local shader = nil

local highlightVBOLayout = {
  { id = 0, name = "position", size = 3 },
}

local instanceVBO = nil
local instanceVBOLayout = {
  { id = 1, name = 'position', size = 3 },
  { id = 2, name = 'radius', size = 1 },
  { id = 3, name = 'height', size = 1 },
  { id = 4, name = 'color', size = 4 },
}

local function makeCylinderVBO(sections)
  local vbo = gl.GetVBO(GL.ARRAY_BUFFER, true)

  local vboData = {}

  for i = 0, sections do
    local theta = 2 * math.pi * i / sections
    local x = math.cos(theta)
    local z = math.sin(theta)

    vboData[#vboData + 1] = x
    vboData[#vboData + 1] = 0
    vboData[#vboData + 1] = z

    vboData[#vboData + 1] = x
    vboData[#vboData + 1] = 1
    vboData[#vboData + 1] = z
  end

  local numVertices = #vboData / 3

  vbo:Define(
    numVertices,
    highlightVBOLayout
  )
  vbo:Upload(vboData)

  return vbo, numVertices
end

local function makeInstanceVBO(layout, vertexVBO, numVertices)
  local vbo = makeInstanceVBOTable(layout, nil, "gfx_highlight_commander_wrecks")
  vbo.vertexVBO = vertexVBO
  vbo.numVertices = numVertices
  vbo.VAO = makeVAOandAttach(vbo.vertexVBO, vbo.instanceVBO)
  return vbo
end

local function initGL4()
  local cylinderVBO, cylinderVertices = makeCylinderVBO(CYLINDER_SECTIONS)
  instanceVBO = makeInstanceVBO(instanceVBOLayout, cylinderVBO, cylinderVertices)

  local engineUniformBufferDefs = LuaShader.GetEngineUniformBufferDefs()
  vsSrc = vsSrc:gsub("//__ENGINEUNIFORMBUFFERDEFS__", engineUniformBufferDefs)
  fsSrc = fsSrc:gsub("//__ENGINEUNIFORMBUFFERDEFS__", engineUniformBufferDefs)
  shader = LuaShader(
    {
      vertex = vsSrc,
      fragment = fsSrc,
    },
    "gfx_highlight_commander_wrecks"
  )
  local shaderCompiled = shader:Initialize()
  return shaderCompiled
end

-- widget code
-- ===========

local highlightUnitNames = {}

local function shouldHighlight(unitName)
  return highlightUnitNames[unitName] or false
end

local function addHighlight(featureID, noUpload)
  local m, dm, e, de, rl, rt = SpringGetFeatureResources(featureID)
  if m > 0 then
    local x, y, z = SpringGetFeaturePosition(featureID)

    local color = DEFAULT_COLOR
    if config.useTeamColor then
      local featureTeamID = SpringGetFeatureTeam(featureID)

      if featureTeamID ~= nil then
        local r, g, b = SpringGetTeamColor(featureTeamID)
        color = { r, g, b, DEFAULT_OPACITY }
      end
    end
    pushElementInstance(
      instanceVBO,
      {
        x, y, z,
        CYLINDER_RADIUS,
        CYLINDER_HEIGHT,
        unpack(color),
      },
      featureID,
      true,
      noUpload
    )
  end
end

local function removeHighlight(featureID, noUpload)
  popElementInstance(instanceVBO, featureID, noUpload)
end

local function checkAddHighlight(featureID, noUpload)
  local resUnitName = SpringGetFeatureResurrect(featureID)
  if resUnitName ~= nil and shouldHighlight(resUnitName) then
    addHighlight(featureID, noUpload)
  end
end

local function checkRemoveHighlight(featureID, noUpload)
  if instanceVBO.instanceIDtoIndex[featureID] ~= nil then
    removeHighlight(featureID, noUpload)
  end
end

local function checkAllFeatures()
  if instanceVBO == nil then
    return
  end

  clearInstanceTable(instanceVBO)

  for _, featureID in ipairs(SpringGetAllFeatures()) do
    checkAddHighlight(featureID, true)
  end

  uploadAllElements(instanceVBO)
end

function widget:DrawWorld()
  if Spring.IsGUIHidden() then
    return
  end

  if instanceVBO.usedElements == 0 then
    return
  end

  gl.DepthTest(GL.LEQUAL)
  shader:Activate()

  instanceVBO.VAO:DrawArrays(
    GL.TRIANGLE_STRIP,
    instanceVBO.numVertices,
    0,
    instanceVBO.usedElements,
    0
  )

  shader:Deactivate()
end

local prevMapDrawMode = nil
local prevSpectatingFullView = nil
function widget:Update(dt)
  local spectating, spectatingFullView = SpringGetSpectatingState()
  local mapDrawMode = SpringGetMapDrawMode()

  if mapDrawMode ~= prevMapDrawMode then
    checkAllFeatures()
  elseif spectatingFullView ~= prevSpectatingFullView then
    checkAllFeatures()
  end

  prevMapDrawMode = mapDrawMode
  prevSpectatingFullView = spectatingFullView
end

function widget:FeatureCreated(featureID, allyTeamID)
  checkAddHighlight(featureID)
end

function widget:FeatureDestroyed(featureID, allyTeamID)
  checkRemoveHighlight(featureID)
end

function widget:PlayerChanged(playerID)
  checkAllFeatures()
end

local OPTION_SPECS = {
  {
    configVariable = "useTeamColor",
    name = "Use Player Color",
    description = "Use the player's color for the beam, instead of the default color (default matches resurrect order color)",
    type = "bool",
  },
}

local function getOptionId(optionSpec)
  return "highlight_commander_wrecks__" .. optionSpec.configVariable
end

local function getWidgetName()
  return "Highlight Commander Wrecks"
end

local function getOptionValue(optionSpec)
  if optionSpec.type == "slider" then
    return config[optionSpec.configVariable]
  elseif optionSpec.type == "bool" then
    return config[optionSpec.configVariable]
  elseif optionSpec.type == "select" then
    -- we have text, we need index
    for i, v in ipairs(optionSpec.options) do
      if config[optionSpec.configVariable] == v then
        return i
      end
    end
  end
end

local function setOptionValue(optionSpec, value)
  if optionSpec.type == "slider" then
    config[optionSpec.configVariable] = value
  elseif optionSpec.type == "bool" then
    config[optionSpec.configVariable] = value
  elseif optionSpec.type == "select" then
    -- we have index, we need text
    config[optionSpec.configVariable] = optionSpec.options[value]
  end

  checkAllFeatures()
end

local function createOnChange(optionSpec)
  return function(i, value, force)
    setOptionValue(optionSpec, value)
  end
end

local function createOptionFromSpec(optionSpec)
  local option = table.copy(optionSpec)
  option.configVariable = nil
  option.enabled = nil
  option.id = getOptionId(optionSpec)
  option.widgetname = getWidgetName()
  option.value = getOptionValue(optionSpec)
  option.onchange = createOnChange(optionSpec)
  return option
end

function widget:Initialize()
  if not gl.CreateShader then
    -- no shader support, so just remove the widget itself, especially for headless
    widgetHandler:RemoveWidget()
    return
  end

  if not initGL4() then
    widgetHandler:RemoveWidget()
    return
  end

  if WG['options'] ~= nil then
    WG['options'].addOptions(map(OPTION_SPECS, createOptionFromSpec))
  end

  highlightUnitNames = {}
  for _, unitDef in pairs(UnitDefs) do
    if unitDef.customParams.iscommander then
      highlightUnitNames[unitDef.name] = true
    end
  end

  checkAllFeatures()
end

function widget:Shutdown()
  if WG['options'] ~= nil then
    WG['options'].removeOptions(map(OPTION_SPECS, getOptionId))
  end

  if instanceVBO and instanceVBO.VAO then
    instanceVBO.VAO:Delete()
  end

  if shader then
    shader:Finalize()
  end
end

function widget:GetConfigData()
  local result = {}
  for _, option in ipairs(OPTION_SPECS) do
    result[option.configVariable] = getOptionValue(option)
  end
  return result
end

function widget:SetConfigData(data)
  for _, option in ipairs(OPTION_SPECS) do
    local configVariable = option.configVariable
    if data[configVariable] ~= nil then
      setOptionValue(option, data[configVariable])
    end
  end
end
