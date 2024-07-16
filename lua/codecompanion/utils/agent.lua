local M = {}

---@alias status
---| "started" # The process has started.
---| "progress" # The process is in progress.
---| "success" # The process has completed successfully.
---| "error" # The process has completed with an error.

--- Announces the start of an operation to the "CodeCompanionAgent" by executing a custom autocmd.
---@param bufnr number: The buffer number associated with the operation.
function M.announce_start(bufnr)
  vim.api.nvim_exec_autocmds("User", { pattern = "CodeCompanionAgent", data = { bufnr = bufnr, status = "started" } })
end

-- Announces the progress of an operation by triggering a custom Vim autocommand.
---@param bufnr number The buffer number where the operation is taking place.
---@param status status The current status of the operation.
---@param stream_output string stream output produced by the operation.
function M.announce_progress(bufnr, status, stream_output)
  vim.api.nvim_exec_autocmds("User", {
    pattern = "CodeCompanionAgent",
    data = {
      bufnr = bufnr,
      status = status,
      error = nil,
      output = nil,
      stream_output = stream_output,
      last_execute = false,
    },
  })
end

--- Announces the end of a process by triggering a custom "User" autocommand event with relevant data.
--- output will append to last use block
---@param bufnr number: The buffer number.
---@param status status: The status of the process.
---@param error table|nil: Any error message if available.
---@param output table|nil: The output of the agent.
---@param last_execute boolean: Is this the last agent in the conversation turn?
function M.announce_end(bufnr, status, error, output, last_execute)
  vim.api.nvim_exec_autocmds("User", {
    pattern = "CodeCompanionAgent",
    data = { bufnr = bufnr, status = status, error = error, output = output, last_execute = last_execute },
  })
end

return M
