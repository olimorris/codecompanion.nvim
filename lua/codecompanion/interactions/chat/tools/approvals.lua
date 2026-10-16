--[[
===============================================================================
    File:       codecompanion/interactions/chat/tools/approvals.lua
    Author:     Oli Morris
-------------------------------------------------------------------------------
    Description:
      This module implements the tool approvals cache for CodeCompanion.
      It tracks which tools have been approved for use in which chat.

      Example:
      {
        -- Chat bufnr
        [1] = {
          -- Tools that have been approved
          edit_file = true,
          read_file = true,
        },
        [2] = {
          run_command = {
            -- Commands that has have approved
            ["ls -la"] = true,
            ["make test"] = true,
          },
          read_file = true,
        },
      }
-------------------------------------------------------------------------------
    Attribution:
      If you use or distribute this code, please credit:
      Oli Morris (https://github.com/olimorris)
===============================================================================
--]]

local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")

---@type table<string, string[]>
local approved = {}

---@alias CodeCompanion.Tools.ApprovalMode "ask"|"auto"|"yolo"

---@type table<number, CodeCompanion.Tools.ApprovalMode>
local modes = {}

---@class CodeCompanion.Tools.Approvals
local Approvals = {}

---Always approve a given tool
---@param bufnr number
---@param args { cmd?: string, tool_name: string }
function Approvals:always(bufnr, args)
  if not args or not args.tool_name then
    return
  end

  local tool_cfg = config.interactions.chat.tools and config.interactions.chat.tools[args.tool_name]

  if not approved[bufnr] then
    approved[bufnr] = {}
  end

  if tool_cfg and tool_cfg.opts and tool_cfg.opts.require_cmd_approval and args.cmd then
    if not approved[bufnr][args.tool_name] then
      approved[bufnr][args.tool_name] = {}
    end
    approved[bufnr][args.tool_name][args.cmd] = true
    return
  end

  approved[bufnr][args.tool_name] = true
end

---Check if a tool has been approved for a given chat buffer, by the mode or by the user
---@param bufnr number
---@param args { cmd?: string, tool_name?: string }
function Approvals:is_approved(bufnr, args)
  args = args or {}
  local mode = self:get_mode(bufnr)
  if mode == "yolo" then
    return true
  end

  local tool_cfg = args.tool_name and config.interactions.chat.tools and config.interactions.chat.tools[args.tool_name]
  local tool_opts = (tool_cfg and tool_cfg.opts) or {}

  -- Tools approved per command are vetted command by command in auto mode, via their safe list or the judge
  if mode == "auto" and not tool_opts.protect and not tool_opts.require_cmd_approval then
    return true
  end

  local approvals = approved[bufnr]
  if not approvals or not args.tool_name then
    return false
  end

  log:debug("Approvals for %s: %s", bufnr, approvals)

  if tool_opts.require_cmd_approval then
    if not approvals[args.tool_name] then
      return false
    end
    return approvals[args.tool_name][args.cmd] == true
  end

  return approvals[args.tool_name] == true
end

---@param bufnr number
---@return CodeCompanion.Tools.ApprovalMode
function Approvals:get_mode(bufnr)
  return modes[bufnr] or config.interactions.chat.tools.opts.approval_mode
end

---@param bufnr number
---@param opts { mode: CodeCompanion.Tools.ApprovalMode }
function Approvals:set_mode(bufnr, opts)
  modes[bufnr] = opts.mode
end

---Toggle between the ask and auto modes for a given chat buffer
---@param bufnr? number
---@return boolean
function Approvals:toggle_yolo_mode(bufnr)
  if not bufnr or bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end

  if self:get_mode(bufnr) == "ask" then
    self:set_mode(bufnr, { mode = "auto" })
    return true
  end

  self:set_mode(bufnr, { mode = "ask" })
  return false
end

---Can a shell command run without asking, in auto mode?
---@param cmd? string
---@return boolean
function Approvals.is_safe_command(cmd)
  if type(cmd) ~= "string" then
    return false
  end

  cmd = vim.trim(cmd)
  if cmd == "" or cmd:find("[;&|<>`\n\r]") or cmd:find("$(", 1, true) then
    return false
  end

  local run_command = config.interactions.chat.tools and config.interactions.chat.tools["run_command"]
  local safe_commands = (run_command and run_command.opts and run_command.opts.safe_commands) or {}
  for _, safe_command in ipairs(safe_commands) do
    if cmd == safe_command or vim.startswith(cmd, safe_command .. " ") then
      return true
    end
  end

  return false
end

---Reset the approvals for a given chat buffer
---@param bufnr number
---@return nil
function Approvals:reset(bufnr)
  approved[bufnr] = nil
  modes[bufnr] = nil
end

---List all approvals
---@return table<string, string[]>
function Approvals.list()
  return approved
end

return Approvals
