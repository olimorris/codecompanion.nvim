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
          insert_edit_into_file = true,
          read_file = true,
        },
        [2] = {
          -- Takes precedence in this chat
          yolo_mode = true,
        },
        [3] = {
          cmd_runner = {
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

---Check if a tool has been approved for a given chat buffer
---If no tool_name is provided, checks if yolo mode is enabled
---@param bufnr number
---@param args { cmd?: string, tool_name?: string }
function Approvals:is_approved(bufnr, args)
  local approvals = approved[bufnr]
  log:debug("Approvals for %d: %s", bufnr, approvals)
  if not approvals then
    return false
  end

  local tool_cfg = args
    and args.tool_name
    and config.interactions.chat.tools
    and config.interactions.chat.tools[args.tool_name]

  -- Check if tool requires command-level approval first
  if tool_cfg and tool_cfg.opts and tool_cfg.opts.require_cmd_approval then
    -- Yolo mode overrides cmd approval requirement
    if approvals.yolo_mode then
      -- But still respect allowed_in_yolo_mode = false
      if tool_cfg.opts.allowed_in_yolo_mode == false then
        return false
      end
      return true
    end

    -- Not in yolo mode, check if this specific command was approved
    if not approvals[args.tool_name] then
      return false
    end
    local cmd_approval = approvals[args.tool_name][args.cmd]
    if cmd_approval == true then
      return true
    end
    return false
  end

  -- Handle yolo mode for regular tools (non-cmd-approval tools)
  if approvals.yolo_mode then
    if not args or not args.tool_name then
      return true
    end

    if tool_cfg and tool_cfg.opts then
      -- Allow users to designate certain tools as not allowed in yolo mode
      if tool_cfg.opts.allowed_in_yolo_mode == false then
        return false
      end
    end

    return true
  end

  if args and args.tool_name then
    return approvals[args.tool_name] == true
  end

  return false
end

---Toggle yolo mode for a given chat buffer
---@param bufnr? number
---@return boolean
function Approvals:toggle_yolo_mode(bufnr)
  if not bufnr or bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end

  if not approved[bufnr] then
    approved[bufnr] = {}
  end

  if approved[bufnr]["yolo_mode"] then
    approved[bufnr]["yolo_mode"] = nil
    return false
  end

  approved[bufnr]["yolo_mode"] = true
  return true
end

---Reset the approvals for a given chat buffer
---@param bufnr number
---@return nil
function Approvals:reset(bufnr)
  approved[bufnr] = nil
end

---List all approvals
---@return table<string, string[]>
function Approvals.list()
  return approved
end

return Approvals
