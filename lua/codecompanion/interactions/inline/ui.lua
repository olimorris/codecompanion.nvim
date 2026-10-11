local adapter_ui = require("codecompanion.adapters.ui")
local adapter_utils = require("codecompanion.adapters.utils")
local adapters = require("codecompanion.adapters")
local async = require("codecompanion.utils.async")
local config = require("codecompanion.config")
local input = require("codecompanion.interactions.shared.input")
local utils = require("codecompanion.utils")

local api = vim.api
local fmt = string.format

local _adapters = {} ---@type table<number, table>

local M = {}

---@param adapter CodeCompanion.HTTPAdapter|CodeCompanion.ACPAdapter
---@return string|nil
local function get_model(adapter)
  if adapter.type == "acp" then
    return vim.tbl_get(adapter, "defaults", "session_config_options", "model")
  end
  return adapter_utils.model(adapter)
end

---The adapter's name, with its model if it has one
---@param adapter CodeCompanion.HTTPAdapter|CodeCompanion.ACPAdapter
---@return string
local function get_adapter_label(adapter)
  local model = get_model(adapter)
  return model and fmt("%s (%s)", adapter.formatted_name, model) or adapter.formatted_name
end

---Remember the adapter and model for the next inline prompt in this buffer
---@param inline CodeCompanion.Inline
---@return nil
local function remember_adapter(inline)
  local bufnr = inline.bufnr
  if not _adapters[bufnr] then
    api.nvim_create_autocmd("BufWipeout", {
      buffer = bufnr,
      once = true,
      callback = function()
        _adapters[bufnr] = nil
      end,
    })
  end

  _adapters[bufnr] = { adapter = inline.adapter.name, model = get_model(inline.adapter) }
end

---Pick one of the agent's models, which it only lists once a session is open
---@param inline CodeCompanion.Inline
---@param opts { on_done: fun() }
---@return nil
local function select_acp_model(inline, opts)
  local inline_acp = require("codecompanion.interactions.inline.adapters.acp")

  async.sync(function()
    local models = inline_acp.list_models({ adapter = inline.adapter })
    if models then
      -- The open session may belong to another buffer, whose model isn't the one picked here
      models.currentModelId = get_model(inline.adapter) or models.currentModelId
    end
    vim.schedule(function()
      adapter_ui.select_model({
        adapter = inline.adapter,
        acp_models = models,
        on_choice = function(model_id)
          if model_id then
            inline.adapter = adapters.resolve(inline.adapter.name, { model = model_id })
          end
          opts.on_done()
        end,
      })
    end)
  end)()
end

---Pick an adapter and then a model
---@param inline CodeCompanion.Inline
---@param opts { on_done: fun() }
---@return nil
local function select_adapter(inline, opts)
  adapter_ui.select_adapter({
    current = inline.adapter.name,
    on_choice = function(name)
      if not name then
        return opts.on_done()
      end
      if name ~= inline.adapter.name then
        inline.adapter = adapters.resolve(name)
      end
      if inline.adapter.type == "acp" then
        return select_acp_model(inline, opts)
      end

      adapter_ui.select_model({
        adapter = inline.adapter,
        on_choice = function(model_id)
          if model_id then
            adapters.set_model({ adapter = inline.adapter, model = model_id })
          end
          opts.on_done()
        end,
      })
    end,
  })
end

---@param inline CodeCompanion.Inline
---@return string
local function get_title(inline)
  if inline.is_continuing then
    return fmt(" Continue · %s ", get_adapter_label(inline.conversation.adapter))
  end
  return fmt(" %s · %s ", config.display.input.title, get_adapter_label(inline.adapter))
end

---Step back into the buffer's conversation and through its prompts, or forward out of it to a new one
---@param inline CodeCompanion.Inline
---@return { history_up: fun(), history_down: fun() }
local function get_conversation_keymaps(inline)
  local prompts = inline.conversation.prompts
  local index, draft = 0, ""

  return {
    history_up = function()
      if not inline.is_continuing then
        inline.is_continuing = true
        return input.set_title(get_title(inline))
      end
      if index == #prompts then
        return
      end
      if index == 0 then
        draft = input.get_content()
      end
      index = index + 1
      input.set_content(prompts[#prompts - index + 1])
    end,
    history_down = function()
      if index == 0 then
        inline.is_continuing = false
        return input.set_title(get_title(inline))
      end
      index = index - 1
      input.set_content(index == 0 and draft or prompts[#prompts - index + 1])
    end,
  }
end

---Open the input box, where the adapter and model can be changed before sending
---@param inline CodeCompanion.Inline
---@param opts { on_submit: fun(input: string) }
---@return nil
function M.open_input(inline, opts)
  local callbacks = {
    change_adapter = function()
      if inline.is_continuing then
        local keys = config.display.input.keymaps.history_down.modes.n
        return utils.notify(
          fmt("Press %s to start a new conversation, then change adapter", vim.iter({ keys }):flatten():next())
        )
      end
      input.hide()
      select_adapter(inline, {
        on_done = function()
          remember_adapter(inline)
          M.open_input(inline, opts)
        end,
      })
    end,
  }
  if inline.conversation then
    callbacks = vim.tbl_extend("force", callbacks, get_conversation_keymaps(inline))
  end

  input.open({
    title = get_title(inline),
    window = { height = config.interactions.inline.display.input.height },
    on_submit = opts.on_submit,
    callbacks = callbacks,
  })
end

---@param bufnr number
---@return { adapter: string, model?: string }|nil
function M.get_picked_adapter(bufnr)
  return _adapters[bufnr]
end

---Show the LLM's reply in a float that stays open until `q` is pressed
---@param reply string
---@param opts { adapter: CodeCompanion.HTTPAdapter }
---@return nil
function M.show_reply(reply, opts)
  local _, winnr = vim.lsp.util.open_floating_preview(vim.split(reply, "\n", { plain = true }), "markdown", {
    border = config.display.input.window.border,
    close_events = {},
    focus_id = "codecompanion_inline_reply",
    max_height = math.floor(vim.o.lines * 0.4),
    max_width = math.floor(vim.o.columns * 0.6),
    title = fmt(" %s ", get_adapter_label(opts.adapter)),
  })
  -- The float's own `q` mapping only works from inside it
  api.nvim_set_current_win(winnr)
end

---@return string
function M.build_diff_banner()
  return fmt("%s for keymaps", config.interactions.shared.keymaps.show_keymaps.modes.n)
end

return M
