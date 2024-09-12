local M = {}

local api = vim.api
local config = require("codecompanion").config
local log = require("codecompanion.utils.log")

local original_buffer_content = {}
local codecompanion_buffers = {}
local revert_timers = {}

local function is_valid_buffer(buf_id)
  return buf_id and api.nvim_buf_is_valid(buf_id)
end

local function safe_get_lines(buf_id)
  if not is_valid_buffer(buf_id) then
    return {}
  end
  return api.nvim_buf_get_lines(buf_id, 0, -1, false)
end

local function set_diff_source(buf_id, source)
  if is_valid_buffer(buf_id) then
    vim.b[buf_id].diffCompGit = source
  end
end

local codecompanion_source = {
  name = "codecompanion",
  attach = function(buf_id)
    if not is_valid_buffer(buf_id) then
      return false
    end
    original_buffer_content[buf_id] = safe_get_lines(buf_id)
    set_diff_source(buf_id, "llm")
    return true
  end,
  detach = function(buf_id)
    original_buffer_content[buf_id] = nil
    set_diff_source(buf_id, "git")
  end,
}

local MiniDiff = require("mini.diff")
local git_source = MiniDiff.gen_source.git()

local function switch_to_codecompanion(buf_id)
  if not codecompanion_buffers[buf_id] then
    codecompanion_buffers[buf_id] = true
    MiniDiff.disable(buf_id)
    MiniDiff.enable(buf_id, { source = codecompanion_source })
    M.update_diff(buf_id)
    set_diff_source(buf_id, "llm")
  end
end

local function switch_to_git(buf_id)
  if codecompanion_buffers[buf_id] then
    codecompanion_buffers[buf_id] = nil
    MiniDiff.disable(buf_id)
    MiniDiff.enable(buf_id, { source = git_source })
    set_diff_source(buf_id, "git")
  end
end

local function schedule_revert_to_git(buf_id, delay)
  if revert_timers[buf_id] then
    revert_timers[buf_id]:stop()
  end
  revert_timers[buf_id] = vim.defer_fn(function()
    switch_to_git(buf_id)
    revert_timers[buf_id] = nil
  end, delay)
end

function M.start_diff(buf_id)
  switch_to_codecompanion(buf_id)
  M.update_diff(buf_id)
end

function M.accept(buf_id)
  M.update_diff(buf_id)
  local revert_delay = config.display.inline.diff.revert_delay or 5 * 60 * 1000
  schedule_revert_to_git(buf_id, revert_delay)
end

function M.reject(buf_id)
  if original_buffer_content[buf_id] then
    api.nvim_buf_set_lines(buf_id, 0, -1, false, original_buffer_content[buf_id])
  end
  switch_to_git(buf_id)
end

function M.update_diff(buf_id)
  if not is_valid_buffer(buf_id) then
    return
  end

  local current_content = safe_get_lines(buf_id)
  pcall(MiniDiff.set_ref_text, buf_id, original_buffer_content[buf_id] or {})
  original_buffer_content[buf_id] = current_content
end

function M.force_git(buf_id)
  buf_id = buf_id or api.nvim_get_current_buf()
  switch_to_git(buf_id)
end

function M.force_codecompanion(buf_id)
  buf_id = buf_id or api.nvim_get_current_buf()
  if not is_valid_buffer(buf_id) then
    log:error("Invalid buffer ID")
    return
  end

  if not original_buffer_content[buf_id] then
    original_buffer_content[buf_id] = safe_get_lines(buf_id)
  end

  switch_to_codecompanion(buf_id)
  M.update_diff(buf_id)
end

function M.get_current_source(buf_id)
  buf_id = buf_id or api.nvim_get_current_buf()
  return vim.b[buf_id].diffCompGit or "git"
end

function M.setup()
  local revert_delay = config.display.inline.diff.revert_delay or 5 * 60 * 1000

  api.nvim_create_autocmd("User", {
    pattern = "CodeCompanionInline*",
    callback = function(args)
      local buf_id = args.buf
      if not is_valid_buffer(buf_id) then
        return
      end

      if args.match == "CodeCompanionInlineStarted" then
        switch_to_codecompanion(buf_id)
      elseif args.match == "CodeCompanionInlineFinished" then
        local current_content = safe_get_lines(buf_id)
        pcall(MiniDiff.set_ref_text, buf_id, original_buffer_content[buf_id] or {})
        original_buffer_content[buf_id] = current_content
        schedule_revert_to_git(buf_id, revert_delay)
        MiniDiff.toggle_overlay()
      end
    end,
  })

  api.nvim_create_autocmd("BufReadPost", {
    callback = function(args)
      local buf_id = args.buf
      if is_valid_buffer(buf_id) and vim.b[buf_id].diffCompGit == nil then
        set_diff_source(buf_id, "git")
      end
    end,
  })
end

return M
