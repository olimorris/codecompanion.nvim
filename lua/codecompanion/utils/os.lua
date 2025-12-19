--[[
  Utility functions for OS operations.
--]]

local M = {}

---Get the Operating System
---@return "windows" | "mac" | "unix" | "unknown"
function M.get_os()
  local os_name

  if vim.fn.has("win32") == 1 then
    os_name = "windows"
  elseif vim.fn.has("macunix") == 1 then
    os_name = "mac"
  elseif vim.fn.has("unix") == 1 then
    os_name = "unix"
  else
    os_name = "unknown"
  end

  return os_name
end

---Build a shell command from the given arguments
---@param args table|string
---@return string[]
function M.build_shell_command(args)
  return {
    (M.os == "windows" and "cmd.exe" or "sh"),
    M.os == "windows" and "/c" or "-c",
    type(args) == "table" and table.concat(args, " ") or args,
  }
end

return M
