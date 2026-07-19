local utils = require("codecompanion.utils")

---@class CodeCompanion.EditedFile
---@field path string The absolute path of the edited file
---@field tool string What made the edit (e.g. "insert_edit_into_file", "create_file", "claude_code")
---@field line? number The first line the edit touched, when known
---@field bufnr? number The buffer the edit was made in, when known

local store = {} ---@type CodeCompanion.EditedFile[]
local positions = {} ---@type table<string, number> Lookup of path to position in the store

local M = {}

---Record an edited file, refreshing its entry if it has been edited before
---@param edit CodeCompanion.EditedFile
---@return nil
local function record(edit)
  if not edit.path or edit.path == "" then
    return
  end

  local position = positions[edit.path]
  if position then
    store[position] = vim.tbl_extend("force", store[position], edit)
    return
  end

  table.insert(store, edit)
  positions[edit.path] = #store
end

---Return the files the LLM has edited, in the order they were first edited
---@return CodeCompanion.EditedFile[]
function M.all()
  return store
end

---Open the edited files in the quickfix list
---@return nil
function M.to_quickfix()
  if #store == 0 then
    return utils.notify("No files have been edited this session", vim.log.levels.WARN)
  end

  local items = {}
  for _, edit in ipairs(store) do
    table.insert(items, {
      filename = edit.path,
      lnum = edit.line or 1,
      text = (edit.tool == "create_file" and "created" or "edited") .. " by " .. edit.tool,
    })
  end

  -- A new list is pushed onto the stack, so :colder restores the user's own list
  vim.fn.setqflist({}, " ", { title = "Files edited by the LLM", items = items })
  vim.cmd.copen()
end

---Track the files an LLM edits for the life of the Neovim instance
---@return nil
function M.setup()
  vim.api.nvim_create_autocmd("User", {
    group = vim.api.nvim_create_augroup("codecompanion.edited_files", { clear = true }),
    pattern = "CodeCompanionFileEdited",
    desc = "Track the files that an LLM edits or creates",
    callback = function(args)
      record(args.data)
    end,
  })
end

return M
