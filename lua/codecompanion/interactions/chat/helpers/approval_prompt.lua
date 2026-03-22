local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")
local ui_utils = require("codecompanion.utils.ui")
local utils = require("codecompanion.utils")

local fmt = string.format

local TOOLS_NS = "CodeCompanion-tools"

local M = {}

---Build the markdown content for the approval prompt
---@param opts table
---@return string
local function build_message(opts)
  local lines = { "", "", "---", "**Approval Required**", "" }

  if opts.prompt then
    table.insert(lines, opts.prompt)
    table.insert(lines, "")
  end

  for _, choice in ipairs(opts.choices) do
    table.insert(lines, fmt("- `%s` - %s", choice.key, choice.label))
  end

  -- table.insert(lines, "")
  table.insert(lines, "---")
  table.insert(lines, "")

  return table.concat(lines, "\n")
end

---Clean up keymaps set for the approval prompt
---@param bufnr number
---@param choices table
local function cleanup_keymaps(bufnr, choices)
  for _, choice in ipairs(choices) do
    pcall(vim.keymap.del, "n", choice.key, { buffer = bufnr })
  end
end

---Clear the "Tools processing" indicator
---@param bufnr number
local function clear_processing_msg(bufnr)
  ui_utils.clear_notification(bufnr, { namespace = TOOLS_NS .. "_" .. tostring(bufnr) })
end

---@class CodeCompanion.ApprovalChoice
---@field key string The keymap to trigger this choice (e.g. "g1")
---@field label string Display label (e.g. "Always approve")
---@field callback function Called when the user selects this choice

---Request approval from the user via the chat buffer
---@param chat CodeCompanion.Chat
---@param opts { id: string|number, prompt?: string, choices: CodeCompanion.ApprovalChoice[] }
---@return nil
function M.request(chat, opts)
  local bufnr = chat.bufnr

  clear_processing_msg(bufnr)

  local content = build_message(opts)
  chat:add_buf_message({ content = content })

  if config.interactions.chat.tools.opts.notify_on_approval then
    utils.notify("Approval required")
  end

  local resolved = false
  for _, choice in ipairs(opts.choices) do
    vim.keymap.set("n", choice.key, function()
      if resolved then
        return
      end
      resolved = true

      log:debug("[approval_prompt] User selected: %s", choice.label)

      cleanup_keymaps(bufnr, opts.choices)

      choice.callback()
    end, {
      buffer = bufnr,
      desc = choice.label,
      silent = true,
      nowait = true,
    })
  end
end

return M
