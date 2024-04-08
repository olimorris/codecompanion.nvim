local config = require("codecompanion.config")
local ui = require("codecompanion.utils.ui")
local util = require("codecompanion.utils.util")
local api = vim.api

local M = {}

---@param bufnr nil|integer
---@return nil|CodeCompanion.Chat
M.buf_get_chat = function(bufnr)
  return require("codecompanion.strategies.chat").buf_get_chat(bufnr)
end

---@param args table
---@return nil|CodeCompanion.Inline
M.inline = function(args)
  local context = util.get_context(api.nvim_get_current_buf(), args)

  return require("codecompanion.strategies.inline")
    .new({
      context = context,
      prompts = {
        {
          role = "system",
          content = function()
            return "I want you to act as a senior "
              .. context.filetype
              .. " developer. I will ask you specific questions and I want you to return raw code only (no codeblocks and no explanations). If you can't respond with code, respond with nothing"
          end,
        },
      },
    })
    :start(args.args)
end

M.add = function(args)
  local bufnr = _G.codecompanion_last_chat_buffer

  if not bufnr then
    return vim.notify("[CodeCompanion.nvim]\nNo chat buffer found", vim.log.levels.WARN)
  end

  local context = util.get_context(api.nvim_get_current_buf(), args)
  local total_lines = api.nvim_buf_line_count(bufnr)

  local content = table.concat(context.lines, "  ")
  api.nvim_buf_set_lines(
    bufnr,
    total_lines,
    total_lines,
    false,
    { context.filename .. ":", "", "```" .. context.filetype .. "", content, "```", "" }
  )
end

---@param args? table
M.chat = function(args)
  local adapter
  local context = util.get_context(api.nvim_get_current_buf(), args)

  if args and args.fargs then
    adapter = config.options.adapters[args.fargs[1]]
  end

  local chat = require("codecompanion.strategies.chat").new({
    context = context,
    adapter = adapter,
  })

  api.nvim_win_set_buf(0, chat.bufnr)
  ui.scroll_to_end(0)
end

M.toggle = function()
  local function buf_toggle(buf, action)
    if action == "show" then
      if config.options.display.chat.type == "float" then
        ui.open_float(buf, {
          display = config.options.display.chat.float_options,
        })
      else
        vim.cmd("buffer " .. buf)
      end
    elseif action == "hide" then
      if config.options.display.chat.type == "float" then
        vim.cmd("hide")
      else
        -- Show the previous buffer
        vim.cmd("buffer " .. vim.fn.bufnr("#"))
      end
    end
  end

  local function fire_event(status, buf)
    return api.nvim_exec_autocmds("User", { pattern = "CodeCompanionChat", data = { action = status, buf = buf } })
  end

  if vim.bo.filetype == "codecompanion" then
    local buf = api.nvim_get_current_buf()
    buf_toggle(buf, "hide")
    fire_event("hide_buffer", buf)
  elseif _G.codecompanion_last_chat_buffer then
    buf_toggle(_G.codecompanion_last_chat_buffer, "show")
    fire_event("show_buffer")
  else
    M.chat()
  end
end

local _cached_actions = {}
M.actions = function(args)
  local actions = require("codecompanion.actions")
  local context = util.get_context(api.nvim_get_current_buf(), args)

  local function picker(items, opts, callback)
    opts = opts or {}
    opts.prompt = opts.prompt or "Select an option"
    opts.columns = opts.columns or { "name", "strategy", "description" }

    require("codecompanion.utils.ui").selector(items, {
      prompt = opts.prompt,
      width = config.options.display.action_palette.width,
      height = config.options.display.action_palette.height,
      format = function(item)
        local formatted_item = {}
        for _, column in ipairs(opts.columns) do
          if item[column] ~= nil then
            table.insert(formatted_item, item[column] or "")
          end
        end
        return formatted_item
      end,
      callback = callback,
    })
  end

  local function selection(item)
    if item.picker and type(item.picker.items) == "table" then
      local picker_opts = {
        prompt = item.picker.prompt,
        columns = item.picker.columns,
      }
      return picker(actions.validate(item.picker.items, context), picker_opts, selection)
    elseif item.picker and type(item.picker.items) == "function" then
      local picker_opts = {
        prompt = item.picker.prompt,
        columns = item.picker.columns,
      }
      picker(actions.validate(item.picker.items(), context), picker_opts, selection)
    elseif item and type(item.callback) == "function" then
      return item.callback(context)
    else
      local Strategy = require("codecompanion.strategy")
      return Strategy.new({
        context = context,
        selected = item,
      }):start(item.strategy)
    end
  end

  if not next(_cached_actions) then
    if config.options.use_default_actions then
      for _, action in ipairs(actions.static.actions) do
        table.insert(_cached_actions, action)
      end
    end
    if config.options.actions and #config.options.actions > 0 then
      for _, action in ipairs(config.options.actions) do
        table.insert(_cached_actions, action)
      end
    end
  end

  local items = actions.validate(_cached_actions, context)

  if items and #items == 0 then
    return vim.notify(
      "[CodeCompanion.nvim]\nNo actions set. Please create some in your config or turn on the defaults",
      vim.log.levels.WARN
    )
  end

  picker(items, { prompt = "CodeCompanion actions", columns = { "name", "strategy", "description" } }, selection)
end

---@param opts nil|table
M.setup = function(opts)
  api.nvim_set_hl(0, "CodeCompanionTokens", { link = "Comment", default = true })
  api.nvim_set_hl(0, "CodeCompanionVirtualText", { link = "Comment", default = true })

  config.setup(opts)
end

return M
