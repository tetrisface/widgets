local root = (arg and arg[1]) or "./"
if string.sub(root, -1) ~= "/" and string.sub(root, -1) ~= "\\" then root = root .. "/" end

PVE_STATS_TEST_ROOT = root

for _, test in ipairs({
	"test_pve_stats_request.lua",
	"test_pve_stats_remote.lua",
	"test_pve_stats_fetch.lua",
	"test_pve_stats_presenter.lua",
	"test_pve_stats_widget.lua",
}) do
	dofile(root .. "tests/" .. test)
end

print("pve_stats test suite: ok")
