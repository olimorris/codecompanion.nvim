local api = vim.api
local log = require("codecompanion.utils.log")
local ui = require("codecompanion.utils.ui")

local M = {}

---@enum CodeCompanion.CopilotToolStatus
M.TOOL_STATUS = {
  start = "start",
  progress = "progress",
  final = "final",
  error = "error",
}

---Set the autocmds for the copilot
---@param copilot CodeCompanion.Copilot
---@param tool CodeCompanion.CopilotTool
M.set_autocmd = function(copilot, tool)
  local ns_id = api.nvim_create_namespace("CodeCompanionCopilotVirtualText")
  local group = "CodeCompanionCopilot_" .. copilot.bufnr

  api.nvim_create_augroup(group, { clear = true })

  return api.nvim_create_autocmd("User", {
    desc = "Handle responses from any copilot tools",
    group = group,
    pattern = "CodeCompanionCopilot",
    callback = function(request)
      ---@type CodeCompanion.CopilotToolChunkResp
      local tool_resp = request.data

      if tool_resp.bufnr ~= copilot.bufnr then
        return
      end

      log:info("copilot tool event: %s", tool_resp)

      if tool_resp.status == M.TOOL_STATUS.start then
        copilot.current_tool = tool

        ui.set_virtual_text(
          copilot.bufnr,
          ns_id,
          "Copilot Tool processing ...",
          --- TODO: add hl group
          { hl_group = "CodeCompanionVirtualTextAgents" }
        )
        return
      end

      if tool_resp.status == M.TOOL_STATUS.progress then
        copilot:add_message({
          role = "assistant",
          content = tool_resp.stream_output,
        })
        return
      end

      api.nvim_buf_clear_namespace(copilot.bufnr, ns_id, 0, -1)

      if tool_resp.status == M.TOOL_STATUS.error then
        copilot:add_message({
          role = "assistant",
          content = tool_resp.error,
        })

        copilot:reset()
        copilot:submit()
      end

      if tool_resp.status == M.TOOL_STATUS.final then
        copilot:add_message({
          role = "assistant",
          content = tool_resp.final_output,
        })

        copilot:reset()
        copilot:submit()
      end

      api.nvim_clear_autocmds({ group = group })
    end,
  })
end

return M
