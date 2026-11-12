local approvals = require("codecompanion.interactions.chat.tools.approvals")
local buf_utils = require("codecompanion.utils.buffers")
local diff = require("codecompanion.interactions.chat.tools.builtin.helpers.diff")
local file_utils = require("codecompanion.utils.files")
local log = require("codecompanion.utils.log")
local utils = require("codecompanion.utils")

local api = vim.api
local fmt = string.format

local M = {}

---@class CodeCompanion.Tool.EditFile.Target
---@field bufnr? number
---@field content string
---@field display_name string
---@field ft string
---@field path string
---@field write fun(content: string): { error?: string }

---@param opts { filepath: string, file_size_limit_mb: number }
---@return { target?: CodeCompanion.Tool.EditFile.Target, error?: string }
local function open_file_for_editing(opts)
  local filepath = opts.filepath
  local path = file_utils.validate_and_normalize_path(filepath)
  if not file_utils.exists(path) or file_utils.is_dir(path) then
    return { error = fmt("`%s` does not exist. Use the path of an existing file", filepath) }
  end

  local stat = vim.uv.fs_stat(path)
  if stat and stat.size > opts.file_size_limit_mb * 1024 * 1024 then
    return {
      error = fmt("`%s` is larger than the %s MB limit for editing", filepath, opts.file_size_limit_mb),
    }
  end

  local ok, original = pcall(file_utils.read, path)
  if not ok then
    log:error("[Edit File Tool] Could not read %s: %s", path, original)
    return { error = fmt("Could not read `%s`", filepath) }
  end

  local target = {
    content = original,
    display_name = vim.fn.fnamemodify(path, ":."),
    ft = vim.filetype.match({ filename = path }) or "text",
    path = path,
    write = function(content)
      local read_ok, current = pcall(file_utils.read, path)
      if not read_ok or current ~= original then
        return { error = "the file changed after the edit was proposed. Read it again and retry" }
      end

      local write_ok, write_err = pcall(file_utils.write_to_path, path, content)
      if not write_ok then
        log:error("[Edit File Tool] Could not write %s: %s", path, write_err)
        return { error = "the file could not be written" }
      end

      local bufnr = vim.fn.bufnr(path)
      if bufnr ~= -1 and api.nvim_buf_is_loaded(bufnr) then
        vim.cmd.checktime(bufnr)
      end

      return {}
    end,
  }

  return { target = target }
end

---Replace the buffer's lines and save it, putting the original lines back if the save fails
---@param opts { bufnr: number, lines: string[], original_lines: string[] }
---@return { error?: string }
local function save_buffer(opts)
  local bufnr = opts.bufnr
  local was_modified = vim.bo[bufnr].modified
  local set_ok, set_err = pcall(api.nvim_buf_set_lines, bufnr, 0, -1, false, opts.lines)
  if not set_ok then
    log:error("[Edit File Tool] Could not change buffer %d: %s", bufnr, set_err)
    return { error = "the buffer could not be changed. It may not be modifiable" }
  end

  local write_ok, write_err = pcall(api.nvim_buf_call, bufnr, function()
    vim.cmd("silent write")
  end)
  if not write_ok then
    log:error("[Edit File Tool] Could not save buffer %d: %s", bufnr, write_err)
    api.nvim_buf_set_lines(bufnr, 0, -1, false, opts.original_lines)
    vim.bo[bufnr].modified = was_modified
    return { error = "the buffer could not be saved. It may be read-only" }
  end

  return {}
end

---@param bufnr number
---@return { target: CodeCompanion.Tool.EditFile.Target }
local function open_buffer_for_editing(bufnr)
  if not api.nvim_buf_is_loaded(bufnr) then
    vim.fn.bufload(bufnr)
  end
  local path = api.nvim_buf_get_name(bufnr)
  local original_lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)

  local target = {
    bufnr = bufnr,
    content = table.concat(original_lines, "\n"),
    display_name = vim.fn.fnamemodify(path, ":."),
    ft = vim.bo[bufnr].filetype,
    path = path,
    write = function(content)
      if not vim.deep_equal(api.nvim_buf_get_lines(bufnr, 0, -1, false), original_lines) then
        return { error = "the buffer changed after the edit was proposed. Read it again and retry" }
      end

      return save_buffer({
        bufnr = bufnr,
        lines = vim.split(content, "\n", { plain = true }),
        original_lines = original_lines,
      })
    end,
  }

  return { target = target }
end

---@param text string
---@return string[]
local function split_lines(text)
  return vim.split((text:gsub("\r\n", "\n")), "\n", { plain = true })
end

---@param opts { from_lines: string[], to_lines: string[] }
---@return number
local function get_first_changed_line(opts)
  for i = 1, math.max(#opts.from_lines, #opts.to_lines) do
    if opts.from_lines[i] ~= opts.to_lines[i] then
      return i
    end
  end
  return 1
end

---Show the new content for review and write it once accepted
---@param tools CodeCompanion.Tools
---@param opts { content: string, messages: { success: string, failure: string }, output_cb: fun(response: table), target: CodeCompanion.Tool.EditFile.Target, tool_name: string }
---@return nil
function M.review(tools, opts)
  local target = opts.target
  local from_lines = split_lines(target.content)
  local to_lines = split_lines(opts.content)

  return diff.review({
    from_lines = from_lines,
    to_lines = to_lines,
    apply = function()
      local written = target.write(opts.content)
      if written.error then
        return opts.output_cb({ status = "error", data = fmt("%s: %s", opts.messages.failure, written.error) })
      end
      utils.fire("FileEdited", {
        bufnr = target.bufnr,
        line = get_first_changed_line({ from_lines = from_lines, to_lines = to_lines }),
        path = target.path,
        tool = opts.tool_name,
      })
      opts.output_cb({ status = "success", data = opts.messages.success })
    end,
    approved = approvals:is_approved(tools.chat.bufnr, { tool_name = opts.tool_name }),
    chat = tools.chat,
    chat_bufnr = tools.chat.bufnr,
    ft = target.ft,
    output_cb = opts.output_cb,
    require_confirmation_after = tools.tool.opts.require_confirmation_after,
    title = target.display_name,
    tool_name = opts.tool_name,
  })
end

---Open a file for editing, through its buffer if it's loaded in Neovim
---@param opts { filepath: string, file_size_limit_mb: number }
---@return { target?: CodeCompanion.Tool.EditFile.Target, error?: string }
function M.open(opts)
  local bufnr = buf_utils.get_bufnr_from_path(opts.filepath)
  if bufnr then
    return open_buffer_for_editing(bufnr)
  end
  return open_file_for_editing(opts)
end

return M
