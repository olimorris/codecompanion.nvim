local BaseSlashCommand = require("codecompanion.slash_commands").BaseSlashCommand
local Job = require("plenary.job")
local Path = require("plenary.path")
local async = require("plenary.async")
local cmp = require("cmp")
local scan = require("plenary.scandir")

--- FileCommand class for inserting file or directory contents into the chat.
--- @class CodeCompanion.FileCommand: CodeCompanion.BaseSlashCommand
--- @field config table Configuration options for the command.
local FileCommand = BaseSlashCommand:extend()

function FileCommand:init(opts)
  opts = opts or {}
  BaseSlashCommand.init(self, opts)
  self.name = "file"
  self.description = "Insert content of a file or directory"
  self.config = {
    show_hidden_files = false,
    max_items = 100,
    sort_order = "name", -- "name" or "modified"
    trailing_slash = true,
    max_file_size = 1024 * 1024, -- 1MB
    max_depth = 3, -- Maximum depth for directory recursion
    doc_preview_lines = 20, -- Number of lines to preview in documentation
  }
end

--- Execute the diagnostics command with the provided chat context and arguments.
---@param completion_item CodeCompanion.SlashCommandCompletionItem
---@param callback fun(completion_item: CodeCompanion.SlashCommandCompletionItem|nil)
---@diagnostic disable-next-line: unused-local
function FileCommand:execute(completion_item, callback)
  local file = self:_parse_input(completion_item.slash_command_args)

  if file:is_dir() then
    self:_insert_directory_content(file)
  else
    self:_insert_file_content(file)
  end

  return callback()
end

--- Parse the input path and resolve it to an absolute Path object.
--- @param input string The input path to parse.
--- @return Path The resolved absolute Path object.
function FileCommand:_parse_input(input)
  if input:match("^~/") then
    return Path:new(vim.fn.expand(input))
  end

  local p = Path:new(input)
  if p:is_absolute() then
    return p
  else
    return Path:new(vim.fn.getcwd(), input)
  end
end

--- Insert the contents of a file into the chat buffer.
--- @param file Path The file to insert.
function FileCommand:_insert_file_content(file)
  local chat = self.get_chat()
  if not chat then
    return callback()
  end

  local bufnr = chat.focus_bufnr
  async.run(function()
    if not file:exists() then
      vim.schedule(function()
        vim.notify("File does not exist: " .. file:absolute(), vim.log.levels.ERROR)
      end)
      return
    end

    if file:_stat().size > self.config.max_file_size then
      vim.schedule(function()
        vim.notify("File is too large to insert: " .. file:absolute(), vim.log.levels.WARN)
      end)
      return
    end

    local content = file:read()
    if not content then
      vim.schedule(function()
        vim.notify("Failed to read file: " .. file:absolute(), vim.log.levels.ERROR)
      end)
      return
    end

    vim.schedule(function()
      local filetype = vim.fn.fnamemodify(file:absolute(), ":e")
      local formatted_content = string.format("```%s %s\n%s\n```", filetype, file:absolute(), content)
      local start_line = vim.api.nvim_buf_line_count(chat.bufnr)
      chat:append_to_buf({ content = formatted_content })
      local end_line = vim.api.nvim_buf_line_count(chat.bufnr)

      -- Create fold
      vim.api.nvim_buf_set_option(chat.bufnr, "foldmethod", "manual")
      vim.cmd(string.format("%d,%dfold", start_line, end_line))

      -- Add virtual text
      local relative_path = file:make_relative(vim.fn.getcwd())
      vim.api.nvim_buf_set_extmark(chat.bufnr, chat.namespace, start_line, 0, {
        virt_text = { { relative_path, "CodeCompanionVirtualText" } },
        virt_text_pos = "eol",
      })
    end)
  end, function() end)
end

--- Insert the contents of a directory into the chat buffer.
--- @param dir Path The directory to insert.
--- @param depth? number The current depth of recursion.
function FileCommand:_insert_directory_content(dir, depth)
  local chat = self.get_chat()
  if not chat then
    return callback()
  end

  local bufnr = chat.focus_bufnr
  depth = depth or 0
  if depth > self.config.max_depth then
    return
  end

  async.run(function()
    local entries = scan.scan_dir(dir:absolute(), {
      hidden = self.config.show_hidden_files,
      add_dirs = true,
      depth = 1,
    })

    local content = depth == 0 and "Directory contents of " .. dir:absolute() .. ":\n\n" or ""
    local indent = string.rep("  ", depth)

    for _, entry in ipairs(entries) do
      local entry_path = Path:new(entry)
      local is_dir = entry_path:is_dir()
      content = content .. indent .. entry_path:filename() .. (is_dir and "/" or "") .. "\n"
      if is_dir then
        self:_insert_directory_content(entry_path, depth + 1)
      end
    end

    vim.schedule(function()
      local start_line = vim.api.nvim_buf_line_count(chat.bufnr)
      chat:append_to_buf({ content = content })
      local end_line = vim.api.nvim_buf_line_count(chat.bufnr)

      if depth == 0 then
        -- Create fold
        vim.api.nvim_buf_set_option(chat.bufnr, "foldmethod", "manual")
        vim.cmd(string.format("%d,%dfold", start_line, end_line))

        -- Add virtual text
        local relative_path = dir:make_relative(vim.fn.getcwd())
        vim.api.nvim_buf_set_extmark(chat.bufnr, chat.namespace, start_line, 0, {
          virt_text = { { relative_path, "Comment" } },
          virt_text_pos = "eol",
        })
      end
    end)
  end, function() end)
end

--- Complete file paths for the command.
--- @param params cmp.SourceCompletionApiParams
--- @param callback fun(response: CodeCompanion.SlashCommandCompletionResponse|nil)
function FileCommand:complete(params, callback)
  local input = params.context.cursor_before_line:match("/file%s*(.*)$") or ""
  local dir = self:_parse_input(Path:new(input):parent():absolute())
  local max_depth = self.config.max_depth

  if not input or input == "" then
    input = vim.fn.getcwd()
    dir = self:_parse_input(Path:new(input):absolute())
  end

  Job:new({
    command = "fd",
    args = {
      "--max-depth",
      max_depth,
      self.config.show_hidden_files and "--hidden" or "",
      "--type",
      "d",
      "--type",
      "f",
      ".",
      dir:absolute(),
    },
    on_exit = vim.schedule_wrap(function(j, return_val)
      if return_val ~= 0 then
        callback()
        return
      end

      local items = {}
      for _, file in ipairs(j:result()) do
        local item = self:_create_completion_item(file, dir:absolute())
        table.insert(items, item)
      end

      items = self:_filter_and_sort(items)
      callback(items)
    end),
  }):start()
end

--- Create a completion item for a file or directory.
--- @param file string The file or directory path.
--- @param base_path string The base path for relative paths.
--- @return table The completion item.
function FileCommand:_create_completion_item(file, base_path)
  local p = Path:new(file)
  local relative_path = p:make_relative(base_path)
  local is_dir = p:is_dir()

  ---@type CodeCompanion.SlashCommandCompletionItem
  local item = {
    label = relative_path,
    kind = is_dir and cmp.lsp.CompletionItemKind.Folder or cmp.lsp.CompletionItemKind.File,
    slash_command_name = self.name,
    slash_command_args = file,
  }

  if is_dir and self.config.trailing_slash then
    item.label = item.label .. "/"
  end

  return item
end

---Resolve completion item (optional). This is called right before the completion is about to be displayed.
---Useful for setting the text shown in the documentation window (`completion_item.documentation`).
---@param completion_item CodeCompanion.SlashCommandCompletionItem
---@param callback fun(completion_item: CodeCompanion.SlashCommandCompletionItem|nil)
function FileCommand:resolve(completion_item, callback)
  if completion_item.slash_command_name == "" or completion_item.slash_command_args == "" then
    return callback()
  end

  if completion_item.documentation then
    return callback(completion_item)
  else
    Job:new({
      command = "head",
      args = {
        "-n",
        string.format("%d", self.config.doc_preview_lines),
        completion_item.slash_command_args,
      },
      on_exit = vim.schedule_wrap(function(j, return_val)
        if return_val ~= 0 then
          callback(completion_item)
          return
        end

        local content = j:result()
        completion_item.documentation = {
          kind = cmp.lsp.MarkupKind.Markdown,
          value = string.format(
            "Content of %s\n```%s\n%s\n```",
            completion_item.slash_command_args,
            vim.fn.fnamemodify(completion_item.slash_command_args, ":e"),
            table.concat(content, "\n")
          ),
        }

        callback(completion_item)
      end),
    }):start()
  end
end

--- Filter and sort completion items.
--- @param items table The items to filter and sort.
--- @return table The filtered and sorted items.
function FileCommand:_filter_and_sort(items)
  if self.config.sort_order == "modified" then
    table.sort(items, function(a, b)
      return a.documentation > b.documentation
    end)
  else
    table.sort(items, function(a, b)
      return a.label < b.label
    end)
  end

  return vim.list_slice(items, 1, self.config.max_items)
end

return FileCommand
