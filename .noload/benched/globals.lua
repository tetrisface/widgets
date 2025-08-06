function widget:GetInfo()
  return {
    name    = "helpers",
    desc    = "",
    author  = "author: BigHead",
    date    = "September 13, 2007",
    license = "GNU GPL, v2 or later",
    layer   = -66786786786,
    handler = true,
    enabled = false -- loaded by default?
  }
end

function LoadHelpers()
  VFS.Include('helpers.lua')
end

WG.LoadHelpers = LoadHelpers
