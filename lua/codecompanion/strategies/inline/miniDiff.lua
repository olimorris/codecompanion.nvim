-- implementing mini.diff for llm changes
-- to see the main logic, please head to the setup function below
local M = {}

local original_buffer_content = {} -- Store the original buffer content
local codecompanion_buffers = {} -- Store which buffers are using CodeCompanion source
local revert_timers = {} -- Store timers for reverting to Git source
local MiniDiff = require("mini.diff")
local git_source = MiniDiff.gen_source.git()
local log = require("codecompanion.utils.log")

---@param buf_id number
---@return boolean Whether
local function is_valid_buffer(buf_id)
  return buf_id and vim.api.nvim_buf_is_valid(buf_id)
end

-- store a buffer variable to know which buffer is using codecompanion
---@param buf_id number
---@param source string
local function set_diff_source(buf_id, source)
  if is_valid_buffer(buf_id) then
    log:debug("Setting diff source for buffer %d to '%s'", buf_id, source)
    vim.b[buf_id].diffCompGit = source
  else
    log:debug("Attempted to set diff source for invalid buffer %d", buf_id)
  end
end

-- Define the codecompanion source for mini.diff to use
---@see https://github.com/echasnovski/mini.nvim/blob/main/doc/mini_diff.txt
---@class CodeCompanionSource
---@field name string
---@field attach fun(buf_id: number): boolean
---@field detach fun(buf_id: number)
local codecompanion_source = {
  name = "codecompanion",
  ---@param buf_id number
  ---@return boolean whether the attachment was successful
  attach = function(buf_id)
    if not is_valid_buffer(buf_id) then
      return false
    end
    original_buffer_content[buf_id] = vim.api.nvim_buf_get_lines(buf_id, 0, -1, false)
    log:trace("original_buffer_content assinged" .. "step 0")
    set_diff_source(buf_id, "llm")
    return true
  end,
  ---@param buf_id number
  detach = function(buf_id)
    original_buffer_content[buf_id] = nil
    log:trace("original_buffer_content detached" .. "step 1")
    set_diff_source(buf_id, "git")
  end,
}

-- used to switch back to diff agaist llm changes
---@param buf_id number
function M.switch_to_codecompanion(buf_id)
  if not codecompanion_buffers[buf_id] then
    log:debug("Switching buffer %d to CodeCompanion source", buf_id)
    codecompanion_buffers[buf_id] = true
    MiniDiff.disable(buf_id)
    MiniDiff.enable(buf_id, { source = codecompanion_source })
    M.update_diff(buf_id)
    set_diff_source(buf_id, "llm")
  else
    log:debug("Buffer %d is already using CodeCompanion source", buf_id)
  end
end

-- used to switch back to diff agaist git, used in 'gr' and 'ga' or by timer.
---@param buf_id number
function M.switch_to_git(buf_id)
  if codecompanion_buffers[buf_id] then
    log:debug("Switching buffer %d to Git source", buf_id)
    codecompanion_buffers[buf_id] = nil
    MiniDiff.disable(buf_id)
    MiniDiff.enable(buf_id, { source = git_source })
    set_diff_source(buf_id, "git")
  else
    log:debug("Buffer %d is already using Git source", buf_id)
  end
end

function M.update_diff(buf_id)
  if not is_valid_buffer(buf_id) then
    return
  end

  local current_content = vim.api.nvim_buf_get_lines(buf_id, 0, -1, false)
  pcall(MiniDiff.set_ref_text, buf_id, original_buffer_content[buf_id] or {})
  original_buffer_content[buf_id] = current_content
  log:trace("original_buffer_content assinged " .. "step 1")
end

-- this function is called every time the diff is updated to schedule return
-- to default behaviour of mini.diff against git, if the user didn't already
-- press 'gr' to reject or 'ga' to accept.
---@param buf_id number
---@param delay number
function M.schedule_revert_to_git(buf_id, delay)
  if revert_timers[buf_id] then
    log:debug("Stopping existing revert timer for buffer %d", buf_id)
    revert_timers[buf_id]:stop()
  end
  log:debug("Scheduling revert to Git source for buffer %d in %d milliseconds", buf_id, delay)
  revert_timers[buf_id] = vim.defer_fn(function()
    M.switch_to_git(buf_id)
    revert_timers[buf_id] = nil
  end, delay)
end

-- setup is the main mechanism/logic for this module.
---@param config? table
function M.setup(config)
  config = config or {}
  local revert_delay = config.revert_delay or 5 * 60 * 1000 -- Default: 5 minutes
  -- MiniDiff.setup({ source = git_source })

  vim.api.nvim_create_autocmd("User", {
    pattern = "CodeCompanionInline*",
    callback = function(args)
      local buf_id = args.buf
      if not is_valid_buffer(buf_id) then
        return
      end

      if args.match == "CodeCompanionInlineStarted" then
        M.switch_to_codecompanion(buf_id)
      elseif args.match == "CodeCompanionInlineFinished" then
        -- local current_content = vim.api.nvim_buf_get_lines(buf_id, 0, -1, false)
        pcall(MiniDiff.set_ref_text, buf_id, original_buffer_content[buf_id] or {})
        -- original_buffer_content[buf_id] = current_content
        log:trace("original_buffer_content assinged " .. "step 2")
        M.schedule_revert_to_git(buf_id, revert_delay)
        MiniDiff.toggle_overlay()
      end
    end,
  })

  vim.api.nvim_create_autocmd("BufReadPost", {
    callback = function(args)
      local buf_id = args.buf
      if is_valid_buffer(buf_id) and vim.b[buf_id].diffCompGit == nil then
        set_diff_source(buf_id, "git")
      end
    end,
  })
end

---@param buf_id number
function M.accept(buf_id)
  if not is_valid_buffer(buf_id) then
    return
  end

  original_buffer_content[buf_id] = vim.api.nvim_buf_get_lines(buf_id, 0, -1, false)
  M.update_diff(buf_id)
  M.switch_to_git(buf_id)
end

---@param buf_id number
function M.reject(buf_id)
  if not is_valid_buffer(buf_id) then
    return
  end

  vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, original_buffer_content[buf_id] or {})
  M.update_diff(buf_id) -- NOTE: why do we do this here again
  M.switch_to_git(buf_id)
end

-- APIS ---------------------------------------------------------------

-- this API function could benefit for the user to know which diff he's using
-- at the current monoment - could be used in the statusline
---@param buf_id? number
---@return string
function M.get_current_source(buf_id)
  buf_id = buf_id or vim.api.nvim_get_current_buf()
  return vim.b[buf_id].diffCompGit or "git"
end

-- API to force switch back to git, could used by keymap
---@param buf_id? number
function M.force_git(buf_id)
  buf_id = buf_id or vim.api.nvim_get_current_buf()
  M.switch_to_git(buf_id)
end

-- API to force switch to codecompanion, could used by keymap
---@param buf_id? number
function M.force_codecompanion(buf_id)
  buf_id = buf_id or vim.api.nvim_get_current_buf()
  if not is_valid_buffer(buf_id) then
    print("Invalid buffer ID")
    return
  end

  -- Ensure we have original content to diff against
  if not original_buffer_content[buf_id] then
    original_buffer_content[buf_id] = vim.api.nvim_buf_get_lines(buf_id, 0, -1, false)
  end

  M.switch_to_codecompanion(buf_id)
  -- Force an update of the diff
  M.update_diff(buf_id)
end

return M
