---@class CodeCompanion.Version
local M = {}

---Get the version of the CodeCompanion plugin
---@return string The version string in format "v17.6.0" or "unknown"
function M.get_version()
  local plugin_path = debug.getinfo(1, "S").source:match("@(.*/)")

  if plugin_path then
    -- Navigate to plugin root (go up from lua/codecompanion/utils/)
    local root_path = plugin_path:gsub("/lua/codecompanion/utils/$", "")

    -- Get version using git describe
    local cmd = string.format("cd '%s' && git describe --tags --always --dirty 2>/dev/null", root_path)
    local handle = io.popen(cmd)
    if handle then
      local result = handle:read("*a")
      handle:close()
      if result and result ~= "" then
        local version = result:gsub("%s+$", "")
        return version
      end
    end
  end

  return "unknown"
end

---Get the User-Agent string for HTTP requests
---@return string The User-Agent string in format "CodeCompanion/v17.6.0"
function M.get_user_agent()
  local version = M.get_version()
  if version == "unknown" then
    return "CodeCompanion"
  else
    -- Remove 'v' prefix if present for consistency
    local clean_version = version:gsub("^v", "")
    return string.format("CodeCompanion/%s", clean_version)
  end
end

return M
