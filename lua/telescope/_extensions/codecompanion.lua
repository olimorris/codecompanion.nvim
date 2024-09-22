local actions_palette = require("codecompanion.actions")
local finders = require("telescope.finders")
local pickers = require("telescope.pickers")
local conf = require("telescope.config").values
local action_state = require("telescope.actions.state")
local telescope_actions = require("telescope.actions")

local cached_opts = {}

local function execute_action(selected, context)
  if selected.callback then
    selected.callback(context)
  elseif selected.strategy then
    local Strategy = require("codecompanion.strategies")
    Strategy.new({
      context = context,
      selected = selected,
    }):start(selected.strategy)
  end
end

local function actions_palette_selector(items, opts, callback, context)
  context = context or require("codecompanion.utils.context").get(vim.api.nvim_get_current_buf())
  opts = vim.tbl_deep_extend("keep", opts or {}, cached_opts)

  pickers
    .new(opts, {
      prompt_title = opts.prompt or "CodeCompanion Actions",
      finder = finders.new_table({
        results = items,
        entry_maker = function(entry)
          return {
            value = entry,
            display = entry.name,
            ordinal = entry.name,
          }
        end,
      }),
      sorter = conf.generic_sorter(opts),
      attach_mappings = function(prompt_bufnr, map)
        telescope_actions.select_default:replace(function()
          local selection = action_state.get_selected_entry()
          local selected = selection.value
          telescope_actions.close(prompt_bufnr)

          if selected.picker then
            local picker_items = selected.picker.items
            if type(picker_items) == "function" then
              picker_items = picker_items(context)
            end
            local picker_opts = vim.tbl_deep_extend("keep", {
              prompt = selected.picker.prompt,
            }, opts)
            actions_palette_selector(picker_items, picker_opts, callback, context)
          else
            if callback then
              callback(selected)
            else
              execute_action(selected, context)
            end
          end
        end)
        return true
      end,
    })
    :find()
end

local function codecompanion(opts)
  cached_opts = opts or {}
  local context = require("codecompanion.utils.context").get(vim.api.nvim_get_current_buf())
  actions_palette_selector(actions_palette.static.actions, cached_opts, nil, context)
end

return require("telescope").register_extension({
  exports = {
    codecompanion = codecompanion,
  },
})
