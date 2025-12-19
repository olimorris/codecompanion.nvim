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
        }
      }
-------------------------------------------------------------------------------
    Attribution:
      If you use or distribute this code, please credit:
      Oli Morris (https://github.com/olimorris)
===============================================================================
--]]

---@type table<string, string[]>
local approved = {}

---@class CodeCompanion.Tools.Approvals
local Approvals = {}

---Add an approval to the cache
---@param bufnr number
---@param args { tool_name: string }
function Approvals:add(bufnr, args)
  if not args or not args.tool_name then
    return
  end

  if not approved[bufnr] then
    approved[bufnr] = {}
  end

  approved[bufnr][args.tool_name] = true
end

---Check if a tool has been approved for a given chat buffer
---@param bufnr number
---@param args { tool_name: string }
function Approvals:is_approved(bufnr, args)
  local approvals = approved[bufnr]
  if not approvals then
    return false
  end

  if approvals.yolo_mode then
    local config = require("codecompanion.config")
    local tool_cfg = config.tools and config.tools[args.tool_name]
    if tool_cfg and tool_cfg.args then
      -- Allow users to designate certain tools as not allowed in yolo mode
      if tool_cfg.args.allowed_in_yolo_mode == false then
        return false
      end
    end
    return true
  end

  return approvals[args.tool_name] == true
end

---Toggle yolo mode for a given chat buffer
---@param bufnr number
---@return nil
function Approvals:toggle_yolo_mode(bufnr)
  if not approved[bufnr] then
    approved[bufnr] = {}
  end

  if approved[bufnr]["yolo_mode"] then
    approved[bufnr]["yolo_mode"] = nil
  else
    approved[bufnr]["yolo_mode"] = true
  end
end

---Reset the approvals for a given chat buffer
---@param bufnr number
---@return nil
function Approvals:reset(bufnr)
  approved[bufnr] = nil
end

return Approvals
