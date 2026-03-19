local file_utils = require("codecompanion.utils.files")
local helpers = require("codecompanion.interactions.chat.tools.builtin.helpers")
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

---Build a lookup of allowed path prefixes and their absolute roots
---@param whitelist? { path: string, as: string }[]
---@return { prefix: string, root: string }[]
local function get_allowed_paths(whitelist)
  local allowed = {
    { prefix = "/" .. CONSTANTS.MEMORY_DIR, root = get_memory_root() },
  }
  for _, entry in ipairs(whitelist or {}) do
    if type(entry.path) == "string" and entry.path ~= "" and type(entry.as) == "string" and entry.as ~= "" then
      local prefix = vim.startswith(entry.as, "/") and entry.as or ("/" .. entry.as)
      table.insert(allowed, { prefix = prefix, root = vim.fs.normalize(entry.path) })
    end
  end

  -- Sort by prefix length descending so longer prefixes match first.
  -- This prevents "/memories" from false-matching "/memoriesbackup"
  table.sort(allowed, function(a, b)
    return #a.prefix > #b.prefix
  end)

  return allowed
end

---Validate and normalize a memory path to prevent directory traversal
---@param path string The path to validate
---@param whitelist? { path: string, as: string }[]
---@return string normalized_path
local function validate_path(path, whitelist)
  if type(path) ~= "string" or path == "" then
    error("Path must be a non-empty string")
  end

  path = vim.trim(path)

  -- Reject null bytes which could bypass security checks
  if path:find("%z") then
    error("Path contains invalid characters")
  end

  local allowed = get_allowed_paths(whitelist)

  -- Find which allowed prefix this path matches
  local matched_root
  for _, entry in ipairs(allowed) do
    if vim.startswith(path, entry.prefix) then
      local rest = path:sub(#entry.prefix + 1)

      -- The character after the prefix must be "/" or end-of-string.
      -- This prevents "/memories" from matching "/memoriesbackup/file.txt"
      if rest ~= "" and not vim.startswith(rest, "/") then
        goto continue
      end

      local relative_path = rest
      if relative_path == "" or relative_path == "/" then
        matched_root = vim.fs.normalize(entry.root)
      else
        matched_root = vim.fs.normalize(vim.fs.joinpath(entry.root, relative_path))
      end
      -- REF: https://docs.claude.com/en/docs/agents-and-tools/tool-use/memory-tool#path-traversal-protection
      if matched_root:match("%.%.") then
        error("Path contains invalid directory traversal sequences")
      end
      local root_normalized = vim.fs.normalize(entry.root)
      if not vim.startswith(matched_root, root_normalized) then
        error(fmt("Invalid path: Must reside within the %s directory", entry.prefix))
      end
      return matched_root
    end

    ::continue::
  end

  -- Build a user-friendly list of valid prefixes
  local prefixes = {}
  for _, entry in ipairs(allowed) do
    table.insert(prefixes, entry.prefix)
  end
  error(fmt("Path must start with one of: %s", table.concat(prefixes, ", ")))
end

---Shows directory contents or file contents with optional line ranges
---@param path string The file or directory path to view
---@param view_range? [number, number] The range of lines to view (start_line, end_line)
---@param whitelist? { path: string, as: string }[]
---@return string content
local function view(path, view_range, whitelist)
  local normalized_path = validate_path(path, whitelist)

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
---@param whitelist? { path: string, as: string }[]
---@return nil
local function create(path, file_text, whitelist)
  local normalized_path = validate_path(path, whitelist)

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
---@param whitelist? { path: string, as: string }[]
---@return nil
local function str_replace(path, old_str, new_str, whitelist)
  local normalized_path = validate_path(path, whitelist)

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
---@param whitelist? { path: string, as: string }[]
---@return nil
local function insert(path, insert_line, insert_text, whitelist)
  local normalized_path = validate_path(path, whitelist)

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
---@param whitelist? { path: string, as: string }[]
---@return nil
local function delete(path, whitelist)
  local normalized_path = validate_path(path, whitelist)

  -- Prevent deletion of any root directory (memories or whitelisted)
  local allowed = get_allowed_paths(whitelist)
  for _, entry in ipairs(allowed) do
    if normalized_path == vim.fs.normalize(entry.root) then
      error(fmt("Cannot delete the root directory: %s", entry.prefix))
    end
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
---@param whitelist? { path: string, as: string }[]
---@return nil
local function rename(old_path, new_path, whitelist)
  local normalized_old = validate_path(old_path, whitelist)
  local normalized_new = validate_path(new_path, whitelist)

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

      local tool_opts = self.tool and self.tool.opts
      local whitelist = tool_opts and tool_opts.whitelist

      log:trace("[Memory Tool] Executing command: %s", command)

      if command == "view" then
        if not args.path then
          return output_msg("error", "The 'view' command requires a 'path' parameter")
        end
        local ok, output = pcall(view, args.path, args.view_range, whitelist)
        if not ok then
          log:debug("[Memory Tool] View error: %s", output)
          return output_msg("error", output)
        end
        return output_msg("success", output)
      end

      if command == "create" then
        if not args.path then
          return output_msg("error", "The 'create' command requires a 'path' parameter")
        end
        local ok, output = pcall(create, args.path, args.file_text, whitelist)
        if not ok then
          log:debug("[Memory Tool] Create error: %s", output)
          return output_msg("error", output)
        end
        return output_msg("success", fmt("Created file: %s", args.path))
      end

      if command == "str_replace" then
        if not args.path then
          return output_msg("error", "The 'str_replace' command requires a 'path' parameter")
        end
        if not args.old_str then
          return output_msg("error", "The 'str_replace' command requires an 'old_str' parameter")
        end
        local ok, output = pcall(str_replace, args.path, args.old_str, args.new_str or "", whitelist)
        if not ok then
          log:debug("[Memory Tool] String replace error: %s", output)
          return output_msg("error", output)
        end
        return output_msg("success", fmt("Replaced text in file: %s", args.path))
      end

      if command == "insert" then
        if not args.path then
          return output_msg("error", "The 'insert' command requires a 'path' parameter")
        end
        if not args.insert_line then
          return output_msg("error", "The 'insert' command requires an 'insert_line' parameter")
        end
        if not args.insert_text then
          return output_msg("error", "The 'insert' command requires an 'insert_text' parameter")
        end
        local ok, output = pcall(insert, args.path, args.insert_line, args.insert_text, whitelist)
        if not ok then
          log:debug("[Memory Tool] Insert error: %s", output)
          return output_msg("error", output)
        end
        return output_msg("success", fmt("Inserted text in file: %s", args.path))
      end

      if command == "delete" then
        if not args.path then
          return output_msg("error", "The 'delete' command requires a 'path' parameter")
        end
        local ok, output = pcall(delete, args.path, whitelist)
        if not ok then
          log:debug("[Memory Tool] Delete error: %s", output)
          return output_msg("error", output)
        end
        return output_msg("success", fmt("Deleted: %s", args.path))
      end

      if command == "rename" then
        if not args.old_path then
          return output_msg("error", "The 'rename' command requires an 'old_path' parameter")
        end
        if not args.new_path then
          return output_msg("error", "The 'rename' command requires a 'new_path' parameter")
        end
        local ok, output = pcall(rename, args.old_path, args.new_path, whitelist)
        if not ok then
          log:debug("[Memory Tool] Rename error: %s", output)
          return output_msg("error", output)
        end
        return output_msg("success", fmt("Renamed %s to %s", args.old_path, args.new_path))
      end

      return output_msg("error", fmt("Unknown command: %s", command))
    end,
  },
  schema = {
    type = "function",
    ["function"] = {
      name = "memory",
      description = "Tool for reading, writing, and managing files in a memory system that lives under /memories. This system records your own memory, and is initialized as an empty folder when the task started. This tool can only change files under /memories. This is your memory, you are free to structure this directory as you see fit.\n* The view command supports the following cases:\n  - Directories: Lists files and directories up to 2 levels deep, ignoring hidden items and node_modules\n  - Image files (.jpg, .jpeg, or .png): Displays the image visually\n  - Text files: Displays numbered lines. Lines are determined from Python's .splitlines() method, which recognizes all standard line breaks. If the file contains more than 16000 characters, the output will be truncated.\n* The create command creates or overwrites text files with the content specified in the file_text parameter.\n* The str_replace command replaces text in a file. Requires an exact, unique match of old_str (whitespace sensitive)\n  - Will fail if old_str doesn't exist or appears multiple times\n  - Omitting new_str deletes the matched text\n* The insert command inserts the text insert_text at the line insert_line.\n* The delete command deletes a file or directory (including all contents if a directory).\n* The rename command renames a file or directory. Both old_path and new_path must be provided.\n* All operations are restricted to files and directories within /memories.\n* You cannot delete or rename /memories itself, only its contents.\n* Note: when editing your memory folder, always try to keep the content up-to-date, coherent and organized. You can rename or delete files that are no longer relevant. Do not create new files unless necessary.",
      parameters = {
        type = "object",
        properties = {
          command = {
            type = "string",
            enum = { "view", "create", "str_replace", "insert", "delete", "rename" },
            description = "The operation to perform. Choose from: view, create, str_replace, insert, delete, rename. See the usage notes below for details.",
          },
          path = {
            type = "string",
            description = "Required for view, create, str_replace, insert, and delete commands. Absolute path to file or directory.",
          },
          view_range = {
            type = "array",
            items = { type = "integer" },
            description = "Optional parameter for the view command (text files only). Format: [start_line, end_line] where lines are indexed starting at 1. Use [start_line, -1] to view from start_line to the end of the file.",
          },
          file_text = {
            type = "string",
            description = "Required for create command. Contains the complete text content to write to the file.",
          },
          old_str = {
            type = "string",
            description = "Required parameter of str_replace command, with string to be replaced. Must be an EXACT and UNIQUE match in the file (be mindful of whitespaces). Tool will fail if multiple matches or no matches are found.",
          },
          new_str = {
            type = "string",
            description = "Optional for str_replace command. The text that will replace old_str. If omitted, old_str will be deleted without replacement.",
          },
          insert_line = {
            type = "integer",
            description = "Required parameter of insert command with line position for insertion: 0 places text at the beginning of the file, N places text after line N, and using the total number of lines in the file places text at the end. Lines in a file are determined using Python's .splitlines() method, which recognizes all standard line breaks.",
          },
          insert_text = {
            type = "string",
            description = "Required parameter of insert command, containing the text to insert. Must end with a newline character for the new text to appear on a separate line from any existing text that follows the insertion point.",
          },
          old_path = {
            type = "string",
            description = "Required for rename command. The current path of the file or directory to rename.",
          },
          new_path = {
            type = "string",
            description = "Required for rename command. The new path for the file or directory.",
          },
        },
        required = { "command" },
      },
    },
  },
  system_prompt = function()
    local config = require("codecompanion.config")
    local tool_config = config.interactions.chat.tools["memory"]
    local whitelist = tool_config and tool_config.opts and tool_config.opts.whitelist

    local prompt =
      [[- Always check the memory tool for relevant context before answering questions about previous conversations.
- Use the memory tool to save important decisions, summaries, or insights from ongoing discussions.
- When context is unclear, search memory for related topics or keywords before responding.
- Prefer updating existing memory entries over creating new ones, unless a new topic is introduced.
- Clearly reference retrieved memory when continuing or summarising conversations.
- If no relevant memory is found, inform the user and ask if they wish to start a new topic or save new context.]]

    if whitelist and #whitelist > 0 then
      local paths = {}
      for _, entry in ipairs(whitelist) do
        if entry.path and entry.as then
          local prefix = vim.startswith(entry.as, "/") and entry.as or ("/" .. entry.as)
          table.insert(paths, fmt("  - %s (mounted at %s)", entry.path, prefix))
        end
      end
      if #paths > 0 then
        prompt = prompt
          .. "\n- In addition to /memories, you can also read and write to these whitelisted paths:\n"
          .. table.concat(paths, "\n")
      end
    end

    return prompt
  end,
  handlers = {
    ---@param self CodeCompanion.Tool.Memory
    ---@param meta { tools: CodeCompanion.Tools }
    ---@return nil
    on_exit = function(self, meta)
      log:trace("[Memory Tool] on_exit handler executed")
    end,
  },
  output = {
    ---The message shared with the user when asking for approval
    ---@param self CodeCompanion.Tools.Tool
    ---@param meta { tools: CodeCompanion.Tools }
    ---@return nil|string
    prompt = function(self, meta)
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
    ---@param stdout table The output from the command
    ---@param meta { tools: CodeCompanion.Tools, cmd: table }
    success = function(self, stdout, meta)
      local chat = meta.tools.chat
      local cmd = meta.cmd

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

    ---@param self CodeCompanion.Tool.Memory
    ---@param stderr table The error output from the command
    ---@param meta { tools: CodeCompanion.Tools, cmd: table }
    error = function(self, stderr, meta)
      local chat = meta.tools.chat

      local errors
      if type(stderr) == "table" then
        errors = table.concat(stderr, "\n")
      end
      if not errors or errors == "" then
        errors = "An unknown error occurred"
      end

      log:debug("[Memory Tool] Error output: %s", errors)

      chat:add_tool_output(self, errors, fmt("Error: %s", errors))
    end,

    ---Rejection message back to the LLM
    ---@param self CodeCompanion.Tool.Memory
    ---@param opts {tools: CodeCompanion.Tools, cmd: string, opts: table }
    ---@return nil
    rejected = function(self, opts)
      local message = "The user rejected the memory operation"
      opts = vim.tbl_extend("force", { message = message }, opts or {})
      helpers.rejected(self, opts)
    end,
  },
}
