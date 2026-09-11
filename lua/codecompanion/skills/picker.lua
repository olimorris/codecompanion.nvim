local utils = require("codecompanion.utils")

---@class CodeCompanion.Skills.PickerItem
---@field name string
---@field description? string
---@field skills string[] The skill names the selection resolves to
---@field path? string Absolute path to the skill's SKILL.md, when it can be previewed

local M = {}

local MAX_NAME_COLUMN = 34

---@param name string
---@param width number
---@return string
local function pad(name, width)
  return name .. string.rep(" ", math.max(width - vim.api.nvim_strwidth(name), 0))
end

---Map a picker's chosen display string back to its item
---@param items table[]
---@param display string
---@return table|nil
local function find_by_display(items, display)
  return vim.iter(items):find(function(item)
    return item.display == display
  end)
end

---@param items table[]
---@return number
local function name_column(items)
  local width = 0
  for _, item in ipairs(items) do
    width = math.max(width, vim.api.nvim_strwidth(item.name))
  end
  return math.min(width, MAX_NAME_COLUMN)
end

---Build the pickers for a list of selectable skills or groups
---@param opts { prompt: string, empty_message: string, preview: boolean, items: fun(): CodeCompanion.Skills.PickerItem[] }
---@return table<string, fun(SlashCommand: CodeCompanion.SlashCommand)>
function M.build(opts)
  ---@return table[]|nil, number
  local function get_items()
    local items = opts.items()
    if vim.tbl_isempty(items) then
      utils.notify(opts.empty_message, vim.log.levels.WARN)
      return nil, 0
    end

    local width = name_column(items)
    for _, item in ipairs(items) do
      item.display = pad(item.name, width) .. "  " .. (item.description or "")
      item.text = item.display
      item.file = item.path
    end

    return items, width
  end

  return {
    ---The default provider
    ---@param SlashCommand CodeCompanion.SlashCommand
    ---@return nil
    default = function(SlashCommand)
      local items = get_items()
      if not items then
        return
      end

      vim.ui.select(items, {
        kind = "codecompanion.nvim",
        prompt = opts.prompt,
        format_item = function(item)
          return item.display
        end,
      }, function(selected)
        if not selected then
          return
        end
        return SlashCommand:output(selected)
      end)
    end,

    ---The Snacks.nvim provider
    ---@param SlashCommand CodeCompanion.SlashCommand
    ---@return nil
    snacks = function(SlashCommand)
      local items, width = get_items()
      if not items then
        return
      end

      local snacks = require("codecompanion.providers.slash_commands.snacks")
      snacks = snacks.new({
        title = opts.prompt .. ": ",
        output = function(selection)
          return SlashCommand:output(selection)
        end,
      })

      local align = snacks.provider.picker.util.align

      snacks.provider.picker.pick({
        title = opts.prompt,
        items = items,
        prompt = snacks.title,
        format = function(item, _)
          return {
            { align(item.name, width, { truncate = true }), "SnacksPickerLabel" },
            { "  " },
            { item.description or "", "SnacksPickerComment" },
          }
        end,
        preview = opts.preview and "file" or "none",
        confirm = snacks:display(),
        main = { file = false, float = true },
      })
    end,

    ---The Telescope provider
    ---@param SlashCommand CodeCompanion.SlashCommand
    ---@return nil
    telescope = function(SlashCommand)
      local items = get_items()
      if not items then
        return
      end

      local telescope = require("codecompanion.providers.slash_commands.telescope")
      telescope = telescope.new({
        title = opts.prompt,
        output = function(selection)
          return SlashCommand:output(selection.value)
        end,
      })

      local values = require("telescope.config").values

      require("telescope.pickers")
        .new({}, {
          prompt_title = telescope.title,
          finder = require("telescope.finders").new_table({
            results = items,
            entry_maker = function(item)
              return { value = item, display = item.display, ordinal = item.display, path = item.path }
            end,
          }),
          sorter = values.generic_sorter({}),
          previewer = opts.preview and values.file_previewer({}) or nil,
          attach_mappings = telescope:display(),
        })
        :find()
    end,

    ---The Mini.Pick provider
    ---@param SlashCommand CodeCompanion.SlashCommand
    ---@return nil
    mini_pick = function(SlashCommand)
      local items = get_items()
      if not items then
        return
      end

      local mini_pick = require("codecompanion.providers.slash_commands.mini_pick")
      mini_pick = mini_pick.new({
        title = opts.prompt,
        output = function(selected)
          return SlashCommand:output(selected)
        end,
      })

      local source = mini_pick:display(function(selected)
        return find_by_display(items, selected)
      end)
      source.source.items = vim.tbl_map(function(item)
        return item.display
      end, items)

      if opts.preview then
        source.source.preview = function(buf_id, display)
          local item = find_by_display(items, display)
          return mini_pick.provider.default_preview(buf_id, item.path)
        end
      end

      mini_pick.provider.start(source)
    end,

    ---The fzf-lua provider
    ---@param SlashCommand CodeCompanion.SlashCommand
    ---@return nil
    fzf_lua = function(SlashCommand)
      local items = get_items()
      if not items then
        return
      end

      local fzf = require("codecompanion.providers.slash_commands.fzf_lua")
      fzf = fzf.new({
        title = opts.prompt,
        output = function(selected)
          return SlashCommand:output(selected)
        end,
      })

      local display = fzf:display(function(selected)
        return find_by_display(items, selected)
      end)

      if opts.preview then
        local previewer = require("fzf-lua.previewer.builtin").buffer_or_file:extend()
        function previewer:parse_entry(entry)
          local item = find_by_display(items, entry)
          return { path = item and item.path }
        end
        display.previewer = previewer
      end

      fzf.provider.fzf_exec(
        vim.tbl_map(function(item)
          return item.display
        end, items),
        display
      )
    end,
  }
end

return M
