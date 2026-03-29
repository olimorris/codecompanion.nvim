local rockspec_path = "codecompanion.nvim-dev-1.rockspec"

-- List all .lua files in the lua/ directory
local handle = io.popen('find lua -name "*.lua" | sort')
if not handle then
  io.stderr:write("Failed to list lua files\n")
  os.exit(1)
end

-- Each module is derived from the filepath. However, we need to remove the "lua/"
-- prefix and the ".lua" suffix, and convert "/" to ".". For example:
-- lua/codecompanion/init.lua -> codecompanion.init
local modules = {}
for path in handle:lines() do
  local module_name = path:gsub("^lua/", ""):gsub("%.lua$", ""):gsub("/", ".")
  modules[#modules + 1] = { name = module_name, path = path }
end
handle:close()

local file = io.open(rockspec_path, "r")
if not file then
  io.stderr:write("Cannot open " .. rockspec_path .. "\n")
  os.exit(1)
end
local content = file:read("*a")
file:close()

-- Format the build.modules section of the rockspec file...
local lines = {}
for _, module in ipairs(modules) do
  lines[#lines + 1] = string.format('    ["%s"] = "%s",', module.name, module.path)
end
local modules_block = table.concat(lines, "\n")

-- Replace everything between `modules = {` and the closing `},`
local marker_open = "modules = {"
local marker_close = "\n  },"

local _, open_end = content:find(marker_open, 1, true)
local close_start = content:find(marker_close, open_end, true)
if not open_end or not close_start then
  io.stderr:write("Could not find modules block in " .. rockspec_path .. "\n")
  os.exit(1)
end

file = io.open(rockspec_path, "w")
if not file then
  io.stderr:write("Cannot write " .. rockspec_path .. "\n")
  os.exit(1)
end
file:write(content:sub(1, open_end) .. "\n" .. modules_block .. content:sub(close_start))
file:close()

print(string.format("Updated %s with %d modules", rockspec_path, #modules))
