---Ref: https://github.com/echasnovski/mini.diff

local log = require("codecompanion.utils.log")

local M = {}

---@type CodeCompanion.Inline
local Inline

local original_buffer_content = {} -- Store the original buffer content
local codecompanion_buffers = {} -- Store which buffers are using CodeCompanion source
local revert_timers = {} -- Store timers for reverting to Git source

local ok, mini_diff = pcall(require, "mini.diff")
if not ok then
  return log:error("Failed to load mini.diff %s", mini_diff)
end

local git_source = mini_diff.gen_source.git()
local REVERT_DELAY = 5 * 60 * 1000 -- 5 minutes

---@param bufnr number
---@return boolean Whether
local function is_valid_buffer(bufnr)
  return bufnr and vim.api.nvim_buf_is_valid(bufnr)
end

-- store a buffer variable to know which buffer is using codecompanion
---@param bufnr number
---@param source string
local function set_diff_source(bufnr, source)
  if is_valid_buffer(bufnr) then
    vim.b[bufnr].diffCompGit = source
  else
  end
end

-- Define the codecompanion source for mini.diff to use
---@see https://github.com/echasnovski/mini.nvim/blob/main/doc/mini_diff.txt
---@class CodeCompanionSource
---@field name string
---@field attach fun(bufnr: number): boolean
---@field detach fun(bufnr: number)
local codecompanion_source = {
  name = "codecompanion",
  ---@param bufnr number
  ---@return boolean whether the attachment was successful
  attach = function(bufnr)
    if not is_valid_buffer(bufnr) then
      return false
    end
    original_buffer_content[bufnr] = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    set_diff_source(bufnr, "llm")
    return true
  end,
  ---@param bufnr number
  detach = function(bufnr)
    original_buffer_content[bufnr] = nil
    set_diff_source(bufnr, "git")
  end,
}

local function update_diff(bufnr)
  if not is_valid_buffer(bufnr) then
    return
  end

  local current_content = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  pcall(mini_diff.set_ref_text, bufnr, original_buffer_content[bufnr] or {})
  original_buffer_content[bufnr] = current_content
end

-- used to switch back to diff agaist llm changes
---@param bufnr number
local function switch_to_codecompanion(bufnr)
  if not codecompanion_buffers[bufnr] then
    codecompanion_buffers[bufnr] = true
    mini_diff.disable(bufnr)
    mini_diff.enable(bufnr, { source = codecompanion_source })
    update_diff(bufnr)
    set_diff_source(bufnr, "llm")
  end
end

-- used to switch back to diff agaist git, used in 'gr' and 'ga' or by timer.
---@param bufnr number
local function switch_to_git(bufnr)
  if codecompanion_buffers[bufnr] then
    codecompanion_buffers[bufnr] = nil
    mini_diff.disable(bufnr)
    mini_diff.enable(bufnr, { source = git_source })
    set_diff_source(bufnr, "git")
  end
end

-- this function is called every time the diff is updated to schedule return
-- to default behaviour of mini.diff against git, if the user didn't already
-- press 'gr' to reject or 'ga' to accept.
---@param bufnr number
---@param delay number
local function schedule_revert_to_git(bufnr, delay)
  if revert_timers[bufnr] then
    revert_timers[bufnr]:stop()
  end
  revert_timers[bufnr] = vim.defer_fn(function()
    switch_to_git(bufnr)
    revert_timers[bufnr] = nil
  end, delay)
end

-- APIS ---------------------------------------------------------------

---Accept the diff
---@return nil
function M.accept()
  original_buffer_content[Inline.context.bufnr] = vim.api.nvim_buf_get_lines(Inline.context.bufnr, 0, -1, false)
  update_diff(Inline.context.bufnr)
  switch_to_git(Inline.context.bufnr)
end

---Reject the diff
---@return nil
function M.reject()
  vim.api.nvim_buf_set_lines(Inline.context.bufnr, 0, -1, false, original_buffer_content[Inline.context.bufnr] or {})
  update_diff(Inline.context.bufnr) -- NOTE: why do we do this here again
  switch_to_git(Inline.context.bufnr)
end

-- setup is the main mechanism/logic for this module.
---@param inline CodeCompanion.Inline
function M.setup(inline)
  Inline = inline
  -- mini_diff.setup({ source = git_source })
  log:trace("Using mini.diff")

  vim.api.nvim_create_autocmd("User", {
    pattern = "CodeCompanionInline*",
    callback = function(args)
      if not args.buf == Inline.context.bufnr then
        return
      end

      local bufnr = Inline.context.bufnr

      if args.match == "CodeCompanionInlineStarted" then
        switch_to_codecompanion(bufnr)
      elseif args.match == "CodeCompanionInlineFinished" then
        -- local current_content = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        pcall(mini_diff.set_ref_text, bufnr, original_buffer_content[bufnr] or {})
        -- original_buffer_content[bufnr] = current_content
        schedule_revert_to_git(bufnr, REVERT_DELAY)
        mini_diff.toggle_overlay()
      end
    end,
  })

  vim.api.nvim_create_autocmd("BufReadPost", {
    callback = function(args)
      local bufnr = args.buf
      if is_valid_buffer(bufnr) and vim.b[bufnr].diffCompGit == nil then
        set_diff_source(bufnr, "git")
      end
    end,
  })
end

return M
