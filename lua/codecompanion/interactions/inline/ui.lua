local adapter_ui = require("codecompanion.adapters.ui")
local adapter_utils = require("codecompanion.adapters.utils")
local adapters = require("codecompanion.adapters")
local async = require("codecompanion.utils.async")
local config = require("codecompanion.config")
local input = require("codecompanion.interactions.shared.input")

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

---Pick one of the agent's models, which it only lists once the buffer's session is open
---@param inline CodeCompanion.Inline
---@param opts { on_done: fun() }
---@return nil
local function select_acp_model(inline, opts)
  local inline_acp = require("codecompanion.interactions.inline.adapters.acp")
  local session = { adapter = inline.adapter, bufnr = inline.bufnr }

  async.sync(function()
    local models = inline_acp.list_models(session)
    vim.schedule(function()
      adapter_ui.select_model({
        adapter = inline.adapter,
        acp_models = models,
        on_choice = function(model_id)
          if not model_id then
            return opts.on_done()
          end
          async.sync(function()
            inline_acp.set_model(vim.tbl_extend("force", session, { model = model_id }))
            inline.adapter = adapters.resolve(inline.adapter.name, { model = model_id })
            vim.schedule(opts.on_done)
          end)()
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

---Open the input box, where the adapter and model can be changed before sending
---@param inline CodeCompanion.Inline
---@param opts { on_submit: fun(input: string) }
---@return nil
function M.open_input(inline, opts)
  input.open({
    title = fmt(" %s · %s ", config.display.input.title, get_adapter_label(inline.adapter)),
    window = { height = config.interactions.inline.display.input.height },
    on_submit = opts.on_submit,
    callbacks = {
      change_adapter = function()
        input.hide()
        select_adapter(inline, {
          on_done = function()
            remember_adapter(inline)
            M.open_input(inline, opts)
          end,
        })
      end,
    },
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
