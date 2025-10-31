local file_utils = require("codecompanion.utils.files")
local helpers = require("codecompanion.strategies.chat.tools.catalog.helpers")
local log = require("codecompanion.utils.log")

local fmt = string.format

local CONSTANTS = {
  MEMORY_DIR = "memories",
}

---Get the absolute memory directory path
---@return string
local function get_memory_root()
  return vim.fs.joinpath(vim.fn.getcwd(), CONSTANTS.MEMORY_DIR)
end

---Validate and normalize a memory path to prevent directory traversal
---@param path string The path to validate (should start with /memories)
---@return string normalized_path
local function validate_path(path)
  path = vim.trim(path)

  -- Path should always start with /memories
  -- REF: https://docs.claude.com/en/docs/agents-and-tools/tool-use/memory-tool#path-traversal-protection
  if not vim.startswith(path, "/" .. CONSTANTS.MEMORY_DIR) then
    error(fmt("Path must start with /%s", CONSTANTS.MEMORY_DIR))
  end

  local relative_path = path:sub(#CONSTANTS.MEMORY_DIR + 2) -- Remove "/memories"
  local absolute_path
  if relative_path == "" or relative_path == "/" then
    absolute_path = get_memory_root()
  else
    absolute_path = vim.fs.joinpath(get_memory_root(), relative_path)
  end

  local normalized = vim.fs.normalize(absolute_path)

  -- Check for directory traversal attempts
  -- REF: https://docs.claude.com/en/docs/agents-and-tools/tool-use/memory-tool#path-traversal-protection
  if normalized:match("%.%.") then
    error("Path contains invalid directory traversal sequences")
  end

  -- Verify the normalized path still resides within memory directory
  local memory_root = vim.fs.normalize(get_memory_root())
  if not vim.startswith(normalized, memory_root) then
    error(fmt("Invalid path: Must reside within the %s directory", CONSTANTS.MEMORY_DIR))
  end

  return normalized
end

---Shows directory contents or file contents with optional line ranges
---@param path string The file or directory path to view
---@param view_range? [number, number] The range of lines to view (start_line, end_line)
---@return string content
local function view(path, view_range)
  local normalized_path = validate_path(path)

  if not file_utils.exists(normalized_path) then
    error(fmt("Path does not exist: %s", path))
  end

  -- Handle directory viewing
  if file_utils.is_dir(normalized_path) then
    local files, err = file_utils.list_dir(normalized_path)
    if not files then
      error(err)
    end

    if #files == 0 then
      return fmt("Directory: %s\n(empty)", path)
    end

    local output = { fmt("Directory: %s", path) }
    for _, file in ipairs(files) do
      table.insert(output, "- " .. file)
    end
    return table.concat(output, "\n")
  end

  local lines, err = file_utils.read_lines(normalized_path)
  if not lines then
    error(err)
  end

  local start_line = view_range and view_range[1] or 1
  local end_line = view_range and view_range[2] or #lines

  -- Validate line range
  if start_line < 1 then
    start_line = 1
  end
  if end_line > #lines then
    end_line = #lines
  end
  if start_line > end_line then
    error("Invalid line range: start_line must be <= end_line")
  end

  local scoped_lines = {}
  for i = start_line, end_line do
    table.insert(scoped_lines, lines[i])
  end

  return table.concat(scoped_lines, "\n")
end

---Create or overwrite a file with content
---@param path string The file path to create
---@param file_text string The content to write
---@return nil
local function create(path, file_text)
  local normalized_path = validate_path(path)

  -- Ensure parent directories exist
  local parent_dir = vim.fn.fnamemodify(normalized_path, ":h")
  local create_dir, err = file_utils.create_dir_recursive(parent_dir)
  if not create_dir then
    error(err)
  end

  local create_file = file_utils.write_to_path(normalized_path, file_text or "")
  if not create_file then
    error(fmt("Failed to create file: %s", path))
  end
end

---Replace text in a file
---@param path string The file path
---@param old_str string The text to find
---@param new_str string The text to replace with
---@return nil
local function str_replace(path, old_str, new_str)
  local normalized_path = validate_path(path)

  if not file_utils.exists(normalized_path) then
    error(fmt("File does not exist: %s", path))
  end

  if file_utils.is_dir(normalized_path) then
    error(fmt("Cannot perform str_replace on a directory: %s", path))
  end

  local content = file_utils.read(normalized_path)
  if not content:find(old_str, 1, true) then
    error(fmt("String not found in file: %s", old_str))
  end

  -- Escape the old string for pattern matching and the new string for replacement
  -- We use plain text find above, but need to escape for gsub
  local escaped_old = vim.pesc(old_str)

  -- Escape % in replacement string (gsub interprets % as special)
  local escaped_new = new_str:gsub("%%", "%%%%")

  local new_content = content:gsub(escaped_old, escaped_new, 1)

  file_utils.write_to_path(normalized_path, new_content)
end

---Insert text at a specific line
---@param path string The file path
---@param insert_line number The line number to insert at (1-indexed)
---@param insert_text string The text to insert
---@return nil
local function insert(path, insert_line, insert_text)
  local normalized_path = validate_path(path)

  if not file_utils.exists(normalized_path) then
    error(fmt("File does not exist: %s", path))
  end
  if file_utils.is_dir(normalized_path) then
    error(fmt("Cannot perform insert on a directory: %s", path))
  end

  local lines, read_err = file_utils.read_lines(normalized_path)
  if not lines then
    error(read_err)
  end
  if insert_line < 1 or insert_line > #lines + 1 then
    error(fmt("Invalid line number %d for file with %d lines", insert_line, #lines))
  end

  table.insert(lines, insert_line, insert_text)
  local new_content = table.concat(lines, "\n")
  file_utils.write_to_path(normalized_path, new_content)
end

---Delete a file or directory
---@param path string The path to delete
---@return nil
local function delete(path)
  local normalized_path = validate_path(path)
  local memory_root = vim.fs.normalize(get_memory_root())

  if normalized_path == memory_root then
    error("Cannot delete the root memory directory")
  end

  if not file_utils.exists(normalized_path) then
    error(fmt("Path does not exist: %s", path))
  end

  local deleted, err = file_utils.delete(normalized_path)
  if not deleted then
    error(err)
  end
end

---Rename or move a file or directory
---@param old_path string The current path
---@param new_path string The new path
---@return nil
local function rename(old_path, new_path)
  local normalized_old = validate_path(old_path)
  local normalized_new = validate_path(new_path)

  if not file_utils.exists(normalized_old) then
    error(fmt("Source path does not exist: %s", old_path))
  end

  if file_utils.exists(normalized_new) then
    error(fmt("Destination path already exists: %s", new_path))
  end

  local success, err = file_utils.rename(normalized_old, normalized_new)
  if not success then
    error(err)
  end
end

---@class CodeCompanion.Tool.Memory: CodeCompanion.Tools.Tool
return {
  name = "memory",
  cmds = {
    ---Execute the memory commands
    ---@param self CodeCompanion.Tool.Memory
    ---@param args table The arguments from the LLM's tool call
    ---@param input? any The output from the previous function call
    ---@return { status: "success"|"error", data: string }
    function(self, args, input)
      local function output_msg(status, msg)
        return { status = status, data = msg }
      end

      local command = args.command
      if not command then
        return output_msg("error", "No command specified")
      end

      log:trace("[Memory Tool] Executing command: %s", command)

      if command == "view" then
        local ok, output = pcall(view, args.path, args.view_range)
        if not ok then
          log:error("[Memory Tool] View error: %s", output)
          return output_msg("error", output)
        end
        return output_msg("success", output)
      end

      if command == "create" then
        local ok, output = pcall(create, args.path, args.file_text)
        if not ok then
          log:error("[Memory Tool] Create error: %s", output)
          return output_msg("error", output)
        end
        return output_msg("success", fmt("Created file: %s", args.path))
      end

      if command == "str_replace" then
        local ok, output = pcall(str_replace, args.path, args.old_str, args.new_str)
        if not ok then
          log:error("[Memory Tool] String replace error: %s", output)
          return output_msg("error", output)
        end
        return output_msg("success", fmt("Replaced text in file: %s", args.path))
      end

      if command == "insert" then
        local ok, output = pcall(insert, args.path, args.insert_line, args.insert_text)
        if not ok then
          log:error("[Memory Tool] Insert error: %s", output)
          return output_msg("error", output)
        end
        return output_msg("success", fmt("Inserted text in file: %s", args.path))
      end

      if command == "delete" then
        local ok, output = pcall(delete, args.path)
        if not ok then
          log:error("[Memory Tool] Delete error: %s", output)
          return output_msg("error", output)
        end
        return output_msg("success", fmt("Deleted: %s", args.path))
      end

      if command == "rename" then
        local ok, output = pcall(rename, args.old_path, args.new_path)
        if not ok then
          log:error("[Memory Tool] Rename error: %s", output)
          return output_msg("error", output)
        end
        return output_msg("success", fmt("Renamed %s to %s", args.old_path, args.new_path))
      end

      return output_msg("error", fmt("Unknown command: %s", command))
    end,
  },
  -- We don't need a schema as this is provided by Anthropic
  handlers = {
    ---@param tools CodeCompanion.Tools The tool object
    ---@return nil
    on_exit = function(tools)
      log:trace("[Memory Tool] on_exit handler executed")
    end,
  },
  output = {
    ---The message shared with the user when asking for approval
    ---@param self CodeCompanion.Tools.Tool
    ---@param tools CodeCompanion.Tools
    ---@return nil|string
    prompt = function(self, tools)
      local args = self.args
      local command = args.command

      if command == "view" then
        return fmt("View %s?", args.path)
      elseif command == "create" then
        return fmt("Create file at %s?", args.path)
      elseif command == "str_replace" then
        return fmt("Replace text in %s?", args.path)
      elseif command == "insert" then
        return fmt("Insert text at line %d in %s?", args.insert_line or 0, args.path)
      elseif command == "delete" then
        return fmt("Delete %s?", args.path)
      elseif command == "rename" then
        return fmt("Rename %s to %s?", args.old_path, args.new_path)
      end

      return "Execute memory command?"
    end,

    ---@param self CodeCompanion.Tool.Memory
    ---@param tools CodeCompanion.Tools
    ---@param cmd table The command that was executed
    ---@param stdout table The output from the command
    success = function(self, tools, cmd, stdout)
      local chat = tools.chat
      local args = self.args

      local llm_output = ""
      local user_output = ""

      if cmd.command == "view" then
        llm_output = fmt('<memoryTool filepath="%s">%s</memoryTool>', cmd.path, vim.iter(stdout):flatten():join("\n"))
        user_output = fmt("Viewed `%s`", cmd.path)
      elseif cmd.command == "create" then
        llm_output = fmt("<memoryTool>Created file at %s</memoryTool>", cmd.path)
        user_output = fmt("Created file at `%s`", cmd.path)
      elseif cmd.command == "str_replace" then
        llm_output = fmt("<memoryTool>Replaced text in %s</memoryTool>", cmd.path)
        user_output = fmt("Replaced text in `%s`", cmd.path)
      elseif cmd.command == "insert" then
        llm_output = fmt("<memoryTool>Inserted text at line %d in %s</memoryTool>", cmd.insert_line, cmd.path)
        user_output = fmt("Inserted text at line %d in `%s`", cmd.insert_line, cmd.path)
      elseif cmd.command == "delete" then
        llm_output = fmt("<memoryTool>Deleted %s</memoryTool>", cmd.path)
        user_output = fmt("Deleted `%s`", cmd.path)
      elseif cmd.command == "rename" then
        llm_output = fmt("<memoryTool>Renamed %s to %s</memoryTool>", cmd.old_path, cmd.new_path)
        user_output = fmt("Renamed `%s` to `%s`", cmd.old_path, cmd.new_path)
      end

      chat:add_tool_output(self, llm_output, user_output)
    end,

    ---@param self CodeCompanion.Tool.CreateFile
    ---@param tools CodeCompanion.Tools
    ---@param cmd table
    ---@param stderr table The error output from the command
    error = function(self, tools, cmd, stderr)
      local chat = tools.chat
      local errors = stderr.data or "Unknown error"
      log:debug("[Memory Tool] Error output: %s", errors)

      chat:add_tool_output(self, errors)
    end,

    ---Rejection message back to the LLM
    ---@param self CodeCompanion.Tool.Memory
    ---@param tools CodeCompanion.Tools
    ---@param cmd table
    ---@param opts table
    ---@return nil
    rejected = function(self, tools, cmd, opts)
      local message = "The user rejected the memory operation"
      opts = vim.tbl_extend("force", { message = message }, opts or {})
      helpers.rejected(self, tools, cmd, opts)
    end,
  },
}
