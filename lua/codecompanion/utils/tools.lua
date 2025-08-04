--[[
	Utility functions for tools
--]]
local M = {}

---Build a shell command from the given arguments
---@param args string[]
---@return string[]
function M.build_shell_command(args)
  return {
    (vim.fn.has("win32") == 1 and "cmd.exe" or "sh"),
    vim.fn.has("win32") == 1 and "/c" or "-c",
    table.concat(args, " "),
  }
end

---Strip any ANSI color codes which don't render in the chat buffer
---@param tbl table
---@return table
function M.strip_ansi(tbl)
  for i, v in ipairs(tbl) do
    tbl[i] = v:gsub("\027%[[0-9;]*%a", "")
  end
  return tbl
end

return M
