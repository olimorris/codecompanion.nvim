local adapter_utils = require("codecompanion.adapters.utils")
local adapters = require("codecompanion.adapters")
local config = require("codecompanion.config")
local input = require("codecompanion.interactions.shared.input")

local api = vim.api
local fmt = string.format

local _adapters = {} ---@type table<number, table>

local M = {}

---The adapter's name, with its model if it has one
---@param adapter CodeCompanion.HTTPAdapter
---@return string
local function get_adapter_label(adapter)
  local model = adapter_utils.model(adapter)
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
  _adapters[bufnr] = { adapter = inline.adapter.name, model = adapter_utils.model(inline.adapter) }
end

---Pick an adapter and then a model, remembering both for the buffer
---@param inline CodeCompanion.Inline
---@param opts { on_done: fun() }
---@return nil
local function select_adapter(inline, opts)
  local change_adapter = require("codecompanion.interactions.chat.keymaps.change_adapter")
  local names = vim.tbl_filter(function(name)
    return config.adapters.http[name] ~= nil
  end, change_adapter.get_adapters_list(inline.adapter.name))

  vim.ui.select(names, { prompt = "Select Adapter", kind = "codecompanion.nvim" }, function(name)
    if not name then
      return opts.on_done()
    end
    if name ~= inline.adapter.name then
      inline.adapter = adapters.resolve(name)
    end

    local models = change_adapter.list_http_models(inline.adapter)
    if not models then
      remember_adapter(inline)
      return opts.on_done()
    end

    vim.ui.select(models, {
      prompt = "Select Model",
      kind = "codecompanion.nvim",
      format_item = function(model)
        return type(model) == "table" and (model.formatted_name or model.id) or model
      end,
    }, function(model)
      if model then
        adapters.set_model({ adapter = inline.adapter, model = type(model) == "table" and model.id or model })
      end
      remember_adapter(inline)
      opts.on_done()
    end)
  end)
end

---Open the input box, where the adapter and model can be changed before sending
---@param inline CodeCompanion.Inline
---@param opts { on_submit: fun(input: string) }
---@return nil
function M.open_input(inline, opts)
  input.open({
    title = fmt(" %s · %s ", config.display.input.title, get_adapter_label(inline.adapter)),
    on_submit = opts.on_submit,
    callbacks = {
      change_adapter = function()
        input.hide()
        select_adapter(inline, {
          on_done = function()
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

---Show the LLM's reply in a float that closes when the cursor moves
---@param reply string
---@param opts { adapter: CodeCompanion.HTTPAdapter }
---@return nil
function M.show_reply(reply, opts)
  vim.lsp.util.open_floating_preview(vim.split(reply, "\n", { plain = true }), "markdown", {
    border = config.display.input.window.border,
    focus_id = "codecompanion_inline_reply",
    max_height = math.floor(vim.o.lines * 0.4),
    max_width = math.floor(vim.o.columns * 0.6),
    title = fmt(" %s ", get_adapter_label(opts.adapter)),
  })
end

---@return string
function M.build_diff_banner()
  return fmt("%s for keymaps", config.interactions.shared.keymaps.show_keymaps.modes.n)
end

return M
