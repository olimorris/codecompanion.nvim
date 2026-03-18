local buf_utils = require("codecompanion.utils.buffers")
local chat_helpers = require("codecompanion.interactions.chat.helpers")
local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")

---@class CodeCompanion.EditorContext.Buffers: CodeCompanion.EditorContext
local EditorContext = {}

---@param args CodeCompanion.EditorContextArgs
function EditorContext.new(args)
  local self = setmetatable({
    Chat = args.Chat,
    buffer_context = args.buffer_context or (args.Chat and args.Chat.buffer_context),
    config = args.config,
    params = args.params,
    target = args.target,
  }, { __index = EditorContext })

  return self
end

---Check if a buffer should be excluded based on the shared editor_context opts
---@param bufnr number
---@return boolean
function EditorContext:_is_excluded(bufnr)
  local ec_opts = config.interactions.shared.editor_context.opts
  local excluded = ec_opts and ec_opts.excluded
  if not excluded then
    return false
  end

  if excluded.buftypes then
    local buftype = vim.bo[bufnr].buftype
    if vim.tbl_contains(excluded.buftypes, buftype) then
      return true
    end
  end

  if excluded.fts then
    local ft = vim.bo[bufnr].filetype
    if vim.tbl_contains(excluded.fts, ft) then
      return true
    end
  end

  return false
end

---Add all open buffers to the chat
---@return nil
function EditorContext:chat_render()
  local buffers = buf_utils.get_open()
  local count = 0

  for _, buf_info in ipairs(buffers) do
    if not self:_is_excluded(buf_info.bufnr) then
      local ok, content, id, _ = pcall(
        chat_helpers.format_buffer_for_llm,
        buf_info.bufnr,
        buf_info.path,
        { message = "Content from an open buffer (including line numbers)" }
      )

      if ok then
        self.Chat:add_message({
          role = config.constants.USER_ROLE,
          content = content,
        }, {
          _meta = { source = "editor_context", tag = "buffer" },
          context = { id = id, path = buf_info.path },
          visible = false,
        })

        self.Chat.context:add({
          bufnr = buf_info.bufnr,
          id = id,
          path = buf_info.path,
          opts = {
            sync_all = true,
          },
          source = "codecompanion.interactions.shared.editor_context.buffer",
        })

        count = count + 1
      end
    end
  end

  if count == 0 then
    log:warn("No open buffers to share")
  end
end

---Return inline label for the CLI interaction
---@return { inline: string }|nil
function EditorContext:cli_render()
  local buffers = buf_utils.get_open()
  local paths = {}

  for _, buf_info in ipairs(buffers) do
    if not self:_is_excluded(buf_info.bufnr) then
      local relative_path = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf_info.bufnr), ":.")
      table.insert(paths, string.format("@%s", relative_path))
    end
  end

  if #paths == 0 then
    log:warn("No open buffers to share")
    return nil
  end

  return {
    inline = "the open buffers: " .. table.concat(paths, ", "),
  }
end

return EditorContext
