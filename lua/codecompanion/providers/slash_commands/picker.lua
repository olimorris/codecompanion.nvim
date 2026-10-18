local files_utils = require("codecompanion.utils.files")
local log = require("codecompanion.utils.log")
local utils = require("codecompanion.utils")

---@class CodeCompanion.SlashCommand.PickerItem
---@field name string
---@field description? string
---@field path? string Absolute path to a file to preview

---@alias CodeCompanion.SlashCommand.ListPickerOpts { prompt: string, empty_message: string, preview: boolean, output: fun(SlashCommand: CodeCompanion.SlashCommand, item: table), items: fun(): CodeCompanion.SlashCommand.PickerItem[] }

local M = {}

local MAX_NAME_COLUMN = 34

---@param name string
---@param width number
---@return string
local function pad(name, width)
  return name .. string.rep(" ", math.max(width - vim.api.nvim_strwidth(name), 0))
end

---Map a picker's chosen display string back to its item
---@param opts { items: table[], display: string }
---@return table|nil
local function find_by_display(opts)
  return vim.iter(opts.items):find(function(item)
    return item.display == opts.display
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

---@param opts CodeCompanion.SlashCommand.ListPickerOpts
---@return table[]|nil, number
local function get_list_items(opts)
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

---Give each picker the options it was built with
---@param opts { pickers: table<string, fun(SlashCommand: CodeCompanion.SlashCommand, opts: table)>, picker_opts: table }
---@return table<string, fun(SlashCommand: CodeCompanion.SlashCommand)>
local function bind_pickers(opts)
  return vim.tbl_map(function(pick)
    return function(SlashCommand)
      return pick(SlashCommand, opts.picker_opts)
    end
  end, opts.pickers)
end

local list_pickers = {}

---@param SlashCommand CodeCompanion.SlashCommand
---@param opts CodeCompanion.SlashCommand.ListPickerOpts
---@return nil
function list_pickers.default(SlashCommand, opts)
  local items = get_list_items(opts)
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
    return opts.output(SlashCommand, selected)
  end)
end

---@param SlashCommand CodeCompanion.SlashCommand
---@param opts CodeCompanion.SlashCommand.ListPickerOpts
---@return nil
function list_pickers.snacks(SlashCommand, opts)
  local items, width = get_list_items(opts)
  if not items then
    return
  end

  local snacks = require("codecompanion.providers.slash_commands.snacks")
  snacks = snacks.new({
    title = opts.prompt .. ": ",
    output = function(selection)
      return opts.output(SlashCommand, selection)
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
end

---@param SlashCommand CodeCompanion.SlashCommand
---@param opts CodeCompanion.SlashCommand.ListPickerOpts
---@return nil
function list_pickers.telescope(SlashCommand, opts)
  local items = get_list_items(opts)
  if not items then
    return
  end

  local telescope = require("codecompanion.providers.slash_commands.telescope")
  telescope = telescope.new({
    title = opts.prompt,
    output = function(selection)
      return opts.output(SlashCommand, selection.value)
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
end

---@param SlashCommand CodeCompanion.SlashCommand
---@param opts CodeCompanion.SlashCommand.ListPickerOpts
---@return nil
function list_pickers.mini_pick(SlashCommand, opts)
  local items = get_list_items(opts)
  if not items then
    return
  end

  local mini_pick = require("codecompanion.providers.slash_commands.mini_pick")
  mini_pick = mini_pick.new({
    title = opts.prompt,
    output = function(selected)
      return opts.output(SlashCommand, selected)
    end,
  })

  local source = mini_pick:display(function(selected)
    return find_by_display({ items = items, display = selected })
  end)
  source.source.items = vim.tbl_map(function(item)
    return item.display
  end, items)

  if opts.preview then
    source.source.preview = function(buf_id, display)
      local item = find_by_display({ items = items, display = display })
      return mini_pick.provider.default_preview(buf_id, item.path)
    end
  end

  mini_pick.provider.start(source)
end

---@param SlashCommand CodeCompanion.SlashCommand
---@param opts CodeCompanion.SlashCommand.ListPickerOpts
---@return nil
function list_pickers.fzf_lua(SlashCommand, opts)
  local items = get_list_items(opts)
  if not items then
    return
  end

  local fzf = require("codecompanion.providers.slash_commands.fzf_lua")
  fzf = fzf.new({
    title = opts.prompt,
    output = function(selected)
      return opts.output(SlashCommand, selected)
    end,
  })

  local display = fzf:display(function(selected)
    return find_by_display({ items = items, display = selected })
  end)
  display.fzf_opts = { ["--multi"] = true }

  if opts.preview then
    local previewer = require("fzf-lua.previewer.builtin").buffer_or_file:extend()
    function previewer:entry_to_file(entry)
      local item = find_by_display({ items = items, display = entry })
      return { path = item and item.path }
    end
    -- fzf-lua's `tbl_deep_extend` merge with its defaults drops the class metatable; `_ctor` survives it
    display.previewer = {
      _ctor = function()
        return previewer
      end,
    }
  end

  fzf.provider.fzf_exec(
    vim.tbl_map(function(item)
      return item.display
    end, items),
    display
  )
end

---Build the pickers for a list of named items
---@param opts { prompt: string, empty_message: string, preview: boolean, output?: fun(SlashCommand: CodeCompanion.SlashCommand, item: table), items: fun(): CodeCompanion.SlashCommand.PickerItem[] }
---@return table<string, fun(SlashCommand: CodeCompanion.SlashCommand)>
function M.build_list_pickers(opts)
  opts = vim.tbl_extend("force", {
    output = function(SlashCommand, item)
      return SlashCommand:output(item)
    end,
  }, opts)

  return bind_pickers({ pickers = list_pickers, picker_opts = opts })
end

---The directories to search in, always led by the current working directory
---@param SlashCommand CodeCompanion.SlashCommand
---@return string[]
local function get_search_dirs(SlashCommand)
  local dirs = { vim.fn.getcwd() }

  local configured = SlashCommand.config.opts and SlashCommand.config.opts.dirs or {}
  for _, dir in ipairs(configured) do
    local path = vim.fs.abspath(vim.fs.normalize(dir))
    if files_utils.is_dir(path) then
      table.insert(dirs, path)
    else
      log:warn("`%s` is not a directory. Skipping", dir)
    end
  end

  return dirs
end

---Every file in the given directories, for pickers that can only search one at a time
---@param dirs string[]
---@return string[]
local function scan_dirs(dirs)
  local files = {}
  for _, dir in ipairs(dirs) do
    vim.list_extend(files, files_utils.scan_dir(dir, { max_depth = 10 }))
  end

  return files
end

---@param path string
---@return { path: string, relative_path: string }
local function make_file_selection(path)
  path = vim.fs.normalize(vim.fs.abspath(path))
  return { path = path, relative_path = vim.fn.fnamemodify(path, ":.") }
end

local file_pickers = {}

---@param SlashCommand CodeCompanion.SlashCommand
---@param opts { prompt: string }
---@return nil
function file_pickers.default(SlashCommand, opts)
  local default = require("codecompanion.providers.slash_commands.default")
  return default
    .new({
      output = function(selection)
        return SlashCommand:output(make_file_selection(selection.path))
      end,
      SlashCommand = SlashCommand,
      title = opts.prompt,
    })
    :find_files({ dirs = get_search_dirs(SlashCommand) })
    :display()
end

---@param SlashCommand CodeCompanion.SlashCommand
---@param opts { prompt: string }
---@return nil
function file_pickers.snacks(SlashCommand, opts)
  local snacks = require("codecompanion.providers.slash_commands.snacks")
  snacks = snacks.new({
    title = opts.prompt .. ": ",
    output = function(selection)
      return SlashCommand:output(make_file_selection(vim.fs.joinpath(selection.cwd, selection.file)))
    end,
  })

  snacks.provider.picker.pick({
    source = "files",
    prompt = snacks.title,
    confirm = snacks:display(),
    dirs = get_search_dirs(SlashCommand),
    main = { file = false, float = true },
  })
end

---@param SlashCommand CodeCompanion.SlashCommand
---@param opts { prompt: string }
---@return nil
function file_pickers.telescope(SlashCommand, opts)
  local telescope = require("codecompanion.providers.slash_commands.telescope")
  telescope = telescope.new({
    title = opts.prompt,
    output = function(selection)
      return SlashCommand:output(make_file_selection(selection.path))
    end,
  })

  telescope.provider.find_files({
    prompt_title = telescope.title,
    attach_mappings = telescope:display(),
    hidden = true,
    search_dirs = get_search_dirs(SlashCommand),
  })
end

---@param SlashCommand CodeCompanion.SlashCommand
---@param opts { prompt: string }
---@return nil
function file_pickers.mini_pick(SlashCommand, opts)
  local mini_pick = require("codecompanion.providers.slash_commands.mini_pick")
  mini_pick = mini_pick.new({
    title = opts.prompt,
    output = function(selection)
      return SlashCommand:output(make_file_selection(selection.path))
    end,
  })

  local display = mini_pick:display(function(selected)
    return { path = selected }
  end)

  local dirs = get_search_dirs(SlashCommand)
  if #dirs == 1 then
    return mini_pick.provider.builtin.files({}, display)
  end

  return mini_pick.provider.start(vim.tbl_deep_extend("force", display, { source = { items = scan_dirs(dirs) } }))
end

---@param SlashCommand CodeCompanion.SlashCommand
---@param opts { prompt: string }
---@return nil
function file_pickers.fzf_lua(SlashCommand, opts)
  local fzf = require("codecompanion.providers.slash_commands.fzf_lua")
  fzf = fzf.new({
    title = opts.prompt,
    output = function(selection)
      return SlashCommand:output(make_file_selection(selection.path))
    end,
  })

  local display = fzf:display(function(selected, fzf_opts)
    return { path = fzf.provider.path.entry_to_file(selected, fzf_opts).path }
  end)

  fzf.provider.files(vim.tbl_extend("force", display, { search_paths = get_search_dirs(SlashCommand) }))
end

---Build the pickers for selecting files from the search directories
---@param opts { prompt: string }
---@return table<string, fun(SlashCommand: CodeCompanion.SlashCommand)>
function M.build_file_pickers(opts)
  return bind_pickers({ pickers = file_pickers, picker_opts = opts })
end

return M
