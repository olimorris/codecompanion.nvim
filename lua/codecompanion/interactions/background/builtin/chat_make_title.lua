local adapters = require("codecompanion.adapters")
local log = require("codecompanion.utils.log")
local tags = require("codecompanion.interactions.shared.tags")

local fmt = string.format

local M = {}

local TITLE_SCHEMA = {
  name = "title",
  schema = {
    type = "object",
    properties = {
      title = { type = "string", description = "A pithy title, 8 words or fewer, capturing the chat's main topic" },
    },
    required = { "title" },
    additionalProperties = false,
  },
  strict = true,
}

---Format the messages from a chat buffer
---@param messages CodeCompanion.Chat.Messages
function M.format_messages(messages)
  local exclude_tags = {
    [tags.IMAGE] = "[Image content omitted]",
    [tags.RULES] = "",
    [tags.SYSTEM_PROMPT_FROM_CONFIG] = "",
  }

  local chat_messages = {}
  for _, m in ipairs(messages or {}) do
    local tag = m._meta and m._meta.tag
    local replacement = exclude_tags[tag]

    if replacement == "" then
      goto continue
    end

    local content = replacement or m.content
    table.insert(chat_messages, fmt("## %s\n%s", m.role, content))

    ::continue::
  end
  return table.concat(chat_messages, "\n")
end

---Handle the result from the title generation request
---@param result table
---@return string|nil
function M.on_done(result)
  if not result or (result.status and result.status == "error") then
    return
  end

  local content = result and result.output and result.output.content
  if not content then
    return
  end

  local ok, decoded = pcall(vim.json.decode, content)
  local title = (ok and type(decoded) == "table" and decoded.title) or content

  title = title:match("^%s*[\"']?(.-)[\"']?%s*$")
  return title and title ~= "" and title or nil
end

---@param background CodeCompanion.Background
---@return boolean
local function supports_structured_output(background)
  local adapter = background.adapter
  return adapters.get_handler(adapter, "build_structured_output") ~= nil
    and adapter.opts ~= nil
    and adapter.opts.can_form_structured_outputs == true
end

---Make the request to generate a title for the chat
---@param background CodeCompanion.Background
---@param chat CodeCompanion.Chat
---@param opts? { deregister: fun() }
function M.request(background, chat, opts)
  if chat.title and chat.title ~= "" then
    if opts and opts.deregister then
      opts.deregister()
    end
    return
  end

  background:ask({
    {
      role = "system",
      content = [[You are an expert in crafting pithy titles for chatbot conversations. You are presented with a chat request, and you reply with a brief title that captures the main topic of that request. Keep your answers short and impersonal.\nThe title should not be wrapped in quotes or contain any sort of formatting such as Markdown or HTML syntax. It should be about 8 words or fewer.\nHere are some examples of good titles:\n- Git rebase question\n- Installing Python packages\n- Location of LinkedList implementation in codebase\n- Adding tests to Neovim plugin\n- React useState hook usage]],
    },
    {
      role = "user",
      content = fmt([[Please write a brief title for the following request:\n\n%s]], M.format_messages(chat.messages)),
    },
  }, {
    method = "async",
    silent = true,
    structured_output = supports_structured_output(background) and TITLE_SCHEMA or nil,
    on_done = function(result)
      local title = M.on_done(result)
      if title then
        chat:set_title(title)
        if opts and opts.deregister then
          opts.deregister()
        end
        log:debug("[Background] Chat title generated: %s", title)
      end
    end,
    on_error = function(err)
      log:debug("[Background] Chat title generation failed: %s", err)
    end,
  })
end

return M
