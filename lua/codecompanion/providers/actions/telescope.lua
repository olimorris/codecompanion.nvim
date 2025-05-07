local finders = require("telescope.finders")
local pickers = require("telescope.pickers")
local conf = require("telescope.config").values
local action_state = require("telescope.actions.state")
local entry_display = require("telescope.pickers.entry_display")
local previewers = require("telescope.previewers")
local telescope_actions = require("telescope.actions")

local log = require("codecompanion.utils.log")

local function wrap_text_to_table(text, max_line_length)
  local lines = {}
  for line in (text .. "\n"):gmatch("(.-)\n") do
    if line == "" then
      table.insert(lines, "")
    else
      local indent, content = line:match("^(%s*)(.*)$")
      local tmp = indent
      for word in content:gmatch("%S+") do
        if #tmp + #word + (#tmp > #indent and 1 or 0) > max_line_length then
          table.insert(lines, tmp)
          tmp = indent .. word
        else
          tmp = (#tmp == #indent) and (indent .. word) or (tmp .. " " .. word)
        end
      end
      if tmp ~= indent then
        table.insert(lines, tmp)
      end
    end
  end
  return lines
end

local action_previewer = previewers.new_buffer_previewer({
  define_preview = function(self, entry)
    local width = vim.api.nvim_win_get_width(self.state.winid) - 4
    entry.preview_command(entry, self.state.bufnr, width)
    vim.api.nvim_buf_set_option(self.state.bufnr, "filetype", "markdown")
  end,
})

local function preview_command(entry, bufnr, width)
  vim.api.nvim_buf_call(bufnr, function()
    local preview = entry.value.description

    if entry.value.prompts and entry.value.prompts[1] then
      local content = entry.value.prompts[1].content
      if type(content) == "string" then
        preview = content
      end
    end

    if preview == "[No messages]" then -- for open chats
      preview = vim.api.nvim_buf_get_lines(entry.value.bufnr, 0, -1, false)
    else
      preview = wrap_text_to_table(preview, width)
    end

    vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, preview)
  end)
end

---@class CodeCompanion.Actions.Provider.Telescope: CodeCompanion.SlashCommand.Provider
local Provider = {}

---@params CodeCompanion.Actions.ProvidersArgs
function Provider.new(args)
  log:trace("Telescope actions provider triggered")
  return setmetatable(args, { __index = Provider })
end

---The Telescope picker
---@param items table The items to display in the picker
---@param opts? table The options for the picker
---@return nil
function Provider:picker(items, opts)
  opts = opts or {}

  local max_name = 1
  for _, item in ipairs(items) do
    max_name = math.max(max_name, #item.name)
  end

  local displayer = entry_display.create({
    separator = " ",
    items = {
      { width = max_name + 1 },
      { remaining = true },
    },
  })

  local function make_display(entry)
    local columns = { entry.value.name }
    if entry.value.strategy then
      columns[2] = { entry.value.strategy, "Comment" }
    end
    return displayer(columns)
  end

  return pickers
    .new(opts, {
      prompt_title = opts.prompt or "CodeCompanion actions",
      finder = finders.new_table({
        results = items,
        entry_maker = function(entry)
          return {
            value = entry,
            display = make_display,
            ordinal = entry.name,
            preview_command = preview_command,
          }
        end,
      }),
      previewer = action_previewer,
      sorter = conf.generic_sorter(opts),
      attach_mappings = function(bufnr, _)
        telescope_actions.select_default:replace(function()
          local selected = action_state.get_selected_entry()
          if not selected or vim.tbl_isempty(selected) then
            return
          end
          telescope_actions.close(bufnr)

          self:select(selected.value)
        end)
        return true
      end,
    })
    :find()
end

---The action to take when an item is selected
---@param item table The selected item
---@return nil
function Provider:select(item)
  return require("codecompanion.providers.actions.shared").select(self, item)
end

return Provider
