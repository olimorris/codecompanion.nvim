local config = require("codecompanion.config")
local document_utils = require("codecompanion.utils.documents")
local log = require("codecompanion.utils.log")

local CONSTANTS = {
  NAME = "Document",
  PROMPT = "Documents",
  DOCUMENT_DIRS = config.interactions.chat.slash_commands.document
      and config.interactions.chat.slash_commands.document.opts
      and config.interactions.chat.slash_commands.document.opts.dirs
    or {},
  DOCUMENT_TYPES = config.interactions.chat.slash_commands.document
      and config.interactions.chat.slash_commands.document.opts
      and config.interactions.chat.slash_commands.document.opts.filetypes
    or { "pdf", "rtf", "docx", "csv", "xslx" },
}

---Prepares document search directories and filetypes
---@return table, table|nil Returns search_dirs and filetypes
local function prepare_document_search_options()
  local current_search_dirs = { vim.fn.getcwd() }

  if CONSTANTS.DOCUMENT_DIRS and vim.tbl_count(CONSTANTS.DOCUMENT_DIRS) > 0 then
    vim.list_extend(current_search_dirs, CONSTANTS.DOCUMENT_DIRS)
  end

  local ft = nil
  if CONSTANTS.DOCUMENT_TYPES and vim.tbl_count(CONSTANTS.DOCUMENT_TYPES) > 0 then
    ft = CONSTANTS.DOCUMENT_TYPES
  end

  return current_search_dirs, ft
end

local providers = {
  ---The default provider
  ---@param SlashCommand CodeCompanion.SlashCommand
  ---@return nil
  default = function(SlashCommand)
    local dirs, ft = prepare_document_search_options()

    local default = require("codecompanion.providers.slash_commands.default")
    default = default
      .new({
        output = function(selection)
          local _res = document_utils.from_path(selection.path, { chat_bufnr = SlashCommand.Chat.bufnr })
          if type(_res) == "string" then
            return log:error(_res)
          end
          return SlashCommand:output(_res)
        end,
        SlashCommand = SlashCommand,
        title = CONSTANTS.PROMPT,
      })
      :documents(dirs, ft)
      :display()
  end,

  ---The Snacks.nvim provider
  ---@param SlashCommand CodeCompanion.SlashCommand
  ---@return nil
  snacks = function(SlashCommand)
    local snacks = require("codecompanion.providers.slash_commands.snacks")
    snacks = snacks.new({
      output = function(selection)
        local _res = document_utils.from_path(selection.file, { chat_bufnr = SlashCommand.Chat.bufnr })
        if type(_res) == "string" then
          return log:error(_res)
        end
        return SlashCommand:output(_res)
      end,
    })

    local dirs, ft = prepare_document_search_options()

    snacks.provider.picker.pick("files", {
      confirm = snacks:display(),
      dirs = dirs,
      ft = ft,
      main = { file = false, float = true },
    })
  end,

  ---The Telescope provider
  ---@param SlashCommand CodeCompanion.SlashCommand
  ---@return nil
  telescope = function(SlashCommand)
    local telescope = require("codecompanion.providers.slash_commands.telescope")
    telescope = telescope.new({
      title = CONSTANTS.PROMPT,
      output = function(selection)
        local _res = document_utils.from_path(selection[1], { chat_bufnr = SlashCommand.Chat.bufnr })
        if type(_res) == "string" then
          return log:error(_res)
        end
        return SlashCommand:output(_res)
      end,
    })

    local dirs, doc_fts = prepare_document_search_options()
    local find_command = { "fd", "--type", "f", "--follow", "--hidden" }
    if doc_fts then
      for _, ext in ipairs(doc_fts) do
        table.insert(find_command, "--extension")
        table.insert(find_command, ext)
      end
    end

    telescope.provider.find_files({
      find_command = find_command,
      prompt_title = telescope.title,
      attach_mappings = telescope:display(),
      search_dirs = dirs,
    })
  end,

  ---The Mini.Pick provider
  ---@param SlashCommand CodeCompanion.SlashCommand
  ---@return nil
  mini_pick = function(SlashCommand)
    local mini_pick = require("codecompanion.providers.slash_commands.mini_pick")
    mini_pick = mini_pick.new({
      title = CONSTANTS.PROMPT,
      output = function(selected)
        local _res = document_utils.from_path(selected.path or selected, { chat_bufnr = SlashCommand.Chat.bufnr })
        if type(_res) == "string" then
          return log:error(_res)
        end
        return SlashCommand:output(_res)
      end,
    })

    local dirs, doc_fts = prepare_document_search_options()
    -- Build glob pattern for mini.pick
    local glob_pattern = "**/*"
    if doc_fts then
      glob_pattern = "**/*.{" .. table.concat(doc_fts, ",") .. "}"
    end

    mini_pick.provider.builtin.files(
      { cwd = dirs[1], glob_pattern = glob_pattern },
      mini_pick:display(function(selected)
        return {
          path = selected,
        }
      end)
    )
  end,

  ---The fzf-lua provider
  ---@param SlashCommand CodeCompanion.SlashCommand
  ---@return nil
  fzf_lua = function(SlashCommand)
    local fzf = require("codecompanion.providers.slash_commands.fzf_lua")
    fzf = fzf.new({
      title = CONSTANTS.PROMPT,
      output = function(selected)
        local file_path = type(selected) == "table" and (selected.path or selected[1]) or selected
        local _res = document_utils.from_path(file_path, { chat_bufnr = SlashCommand.Chat.bufnr })
        if type(_res) == "string" then
          return log:error(_res)
        end
        return SlashCommand:output(_res)
      end,
    })

    local dirs, doc_fts = prepare_document_search_options()
    -- Build file extension filter for fzf
    local ext_pattern = "*"
    if doc_fts then
      ext_pattern = "*.{" .. table.concat(doc_fts, ",") .. "}"
    end

    fzf.provider.files(
      fzf:display(function(selected, opts)
        local file = fzf.provider.path.entry_to_file(selected, opts)
        return {
          relative_path = file.stripped,
          path = file.path,
        }
      end),
      {
        cwd = dirs[1],
        file_icons = true,
        find_opts = ext_pattern,
      }
    )
  end,
}

local choice = {
  ---Load the file picker
  ---@param SlashCommand CodeCompanion.SlashCommand.Document
  ---@param SlashCommands CodeCompanion.SlashCommands
  ---@return nil
  File = function(SlashCommand, SlashCommands)
    return SlashCommands:set_provider(SlashCommand, providers)
  end,

  ---Share the URL of a document
  ---@param SlashCommand CodeCompanion.SlashCommand.Document
  ---@return nil
  URL = function(SlashCommand, _)
    return vim.ui.input({ prompt = "Enter the document URL: " }, function(url)
      if #vim.trim(url or "") == 0 then
        return
      end

      document_utils.from_url(url, { chat_bufnr = SlashCommand.Chat.bufnr }, function(_res)
        if type(_res) == "string" then
          return log:error(_res)
        end
        SlashCommand:output(_res)
      end)
    end)
  end,

  ---Use Files API reference
  ---@param SlashCommand CodeCompanion.SlashCommand.Document
  ---@return nil
  ["Files API"] = function(SlashCommand, _)
    return vim.ui.input({ prompt = "Enter the file_id: " }, function(file_id)
      if #vim.trim(file_id or "") == 0 then
        return
      end

      SlashCommand:output({
        source = "file",
        file_id = file_id,
        id = file_id,
        path = "", -- Required field, empty for Files API references
      })
    end)
  end,
}

---@class CodeCompanion.SlashCommand.Document: CodeCompanion.SlashCommand
local SlashCommand = {}

---@param args CodeCompanion.SlashCommandArgs
function SlashCommand.new(args)
  local self = setmetatable({
    Chat = args.Chat,
    config = args.config,
    context = args.context,
  }, { __index = SlashCommand })

  return self
end

---Execute the slash command
---@param SlashCommands CodeCompanion.SlashCommands
---@return nil
function SlashCommand:execute(SlashCommands)
  vim.ui.select({ "URL", "File", "Files API" }, {
    prompt = "Select a document source",
  }, function(selected)
    if not selected then
      return
    end
    return choice[selected](self, SlashCommands)
  end)
end

---Add document to chat buffer
---@param selected CodeCompanion.Document
---@param opts? table
---@return nil
function SlashCommand:output(selected, opts)
  if selected.source == "file" then
    -- Files API reference - no encoding needed
    return self.Chat:add_document_message(selected)
  end

  local encoded_document = document_utils.encode_document(selected)
  if type(encoded_document) == "string" then
    return log:error("Could not encode document: %s", encoded_document)
  end
  return self.Chat:add_document_message(encoded_document)
end

---Is the slash command enabled?
---@param chat CodeCompanion.Chat
---@return boolean, string
function SlashCommand.enabled(chat)
  -- Check if adapter supports PDF/document processing
  -- PDF support is part of vision capabilities in Claude
  local supports_docs = chat.adapter.opts and chat.adapter.opts.vision -- PDF support piggybacks on vision for now
    or false

  return supports_docs, "The document Slash Command is not enabled for this adapter"
end

return SlashCommand
