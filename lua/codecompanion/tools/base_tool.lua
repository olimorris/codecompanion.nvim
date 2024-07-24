local api = vim.api
local TOOL_STATUS = require("codecompanion.tools.autocmd").TOOL_STATUS
local ctcr = require("codecompanion.tools.chunk")
local log = require("codecompanion.utils.log")

---@enum EXECUTE_TYPE
CODECOMPANION_COPILOT_TOOL_EXECUTE_TYPE = {
  sync = 0,
  stream = 1,
}

---@class CodeCompanion.CopilotTool
---@field name string
---@field copilot CodeCompanion.Copilot
local BaseTool = { name = "base_tool" }
BaseTool.__index = BaseTool

---@param chat CodeCompanion.Chat
function BaseTool.new(chat)
  local self = setmetatable({ copilot = chat }, BaseTool)
  return self
end

---@param chunk CodeCompanion.CopilotToolChunkResp
function BaseTool:send(chunk)
  chunk.bufnr = self.copilot.bufnr
  api.nvim_exec_autocmds("User", { pattern = "CodeCompanionCopilot", data = chunk })
end

--- Executes the tool's operation with the provided arguments.
--- Sends a start and progress response to the copilot buffer,
--- and handles the execution asynchronously.
---
--- @param args string|nil The arguments needed to execute the tool's operation.
--- @return nil
function BaseTool:run(args)
  self:send(ctcr.new_start(self.copilot.bufnr))

  --- some api like deepseek will return stop words so when the last line is stop words
  --- we do not need send "output:==" to chat buffer
  local ll, _, _ = self.copilot:last()
  local last_line = api.nvim_buf_get_lines(self.copilot.bufnr, ll, ll + 1, false)

  if last_line and #last_line > 0 and last_line[1]:match("*output*") then
    self:send(ctcr.new_progress(self.copilot.bufnr, "\n```\n"))
  else
    self:send(ctcr.new_progress(self.copilot.bufnr, "\noutput:==\n```\n"))
  end

  vim.schedule(function()
    ---@param chunk CodeCompanion.CopilotToolChunkResp
    self:execute(args, function(chunk)
      if chunk.status == TOOL_STATUS.final then
        -- when subclass tool send a final chunk
        -- we should close the code block and send the final chunk
        if chunk.final_output == nil then
          chunk.final_output = "\n```\n"
        else
          chunk.final_output = chunk.final_output .. "\n```\n"
        end
      end

      if chunk.status == TOOL_STATUS.error then
        -- when subclass tool send a final chunk
        -- we should close the code block and send the final chunk
        if chunk.error == nil then
          chunk.error = "\n```\n"
        else
          chunk.error = chunk.error .. "\n```\n"
        end
      end

      self:send(chunk)
    end)
  end)
end

-- Executes the tool's functionality with the given arguments.
-- This method must be implemented by subclasses of BaseTool.
--
---@param args string|nil A table containing the arguments necessary for execution.
---@param callback fun(response: CodeCompanion.CopilotToolChunkResp)
function BaseTool:execute(args, callback)
  error("execute method must be implemented by sync tool subclass")
end

function BaseTool:description()
  error("description method must be implemented by subclass")
end

function BaseTool:input_format()
  error("input_format method must be implemented by subclass")
end

function BaseTool:output_format()
  error("output_format method must be implemented by subclass")
end

function BaseTool:example()
  error("example method must be implemented by subclass")
end

return BaseTool
