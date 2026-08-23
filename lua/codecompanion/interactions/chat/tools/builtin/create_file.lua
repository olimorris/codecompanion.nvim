local approvals = require("codecompanion.interactions.chat.tools.approvals")
local diff = require("codecompanion.interactions.chat.tools.builtin.helpers.diff")
local files = require("codecompanion.utils.files")
local helpers = require("codecompanion.interactions.chat.tools.builtin.helpers")
local log = require("codecompanion.utils.log")
local utils = require("codecompanion.utils")

local fmt = string.format

---Validate that a file can be created at the given path
---@param filepath string The absolute path to check
---@return boolean ok
---@return string|nil error_message
local function validate_creation_path(filepath)
  if not files.exists(filepath) then
    return true, nil
  end

  return false, fmt([[Failed creating `%s` - File/directory already exists]], filepath)
end

---Create a file and the surrounding folders
---@param action {filepath: string, content: string} The action containing the filepath and content
---@return {status: "success"|"error", data: string}
local function create(action)
  local filepath = vim.fs.normalize(action.filepath)

  local ok, error_message = validate_creation_path(filepath)
  if not ok then
    return { status = "error", data = error_message }
  end

  local write_ok, write_err = pcall(files.write_to_path, filepath, action.content or "")
  if not write_ok then
    local full_error = fmt([[Failed creating `%s` - %s]], action.filepath, write_err)
    log:error(full_error)
    return { status = "error", data = full_error }
  end

  utils.fire("FileEdited", { path = filepath, tool = "create_file" })
  return {
    status = "success",
    data = fmt([[Created `%s`]], action.filepath),
  }
end

---@class CodeCompanion.Tool.CreateFile: CodeCompanion.Tools.Tool
return {
  name = "create_file",
  cmds = {
    ---Execute the file commands
    ---@param self CodeCompanion.Tools
    ---@param args table The arguments from the LLM's tool call
    ---@param opts { output_cb: fun(response: {status: "success"|"error", data: string}) }
    ---@return nil
    function(self, args, opts)
      local filepath = vim.fs.normalize(args.filepath)

      local ok, error_message = validate_creation_path(filepath)
      if not ok then
        return opts.output_cb({ status = "error", data = error_message })
      end

      local display_path = vim.fn.fnamemodify(args.filepath, ":.")

      return diff.review({
        from_lines = {},
        to_lines = vim.split(args.content or "", "\n", { plain = true }),
        apply = function()
          opts.output_cb(create(args))
        end,
        approved = approvals:is_approved(self.chat.bufnr, { tool_name = "create_file" }),
        chat = self.chat,
        chat_bufnr = self.chat.bufnr,
        ft = vim.filetype.match({ filename = filepath }) or "text",
        output_cb = opts.output_cb,
        require_confirmation_after = self.tool.opts.require_confirmation_after,
        title = display_path,
        tool_name = "create_file",
      })
    end,
  },
  schema = {
    type = "function",
    ["function"] = {
      name = "create_file",
      description = "This is a tool for creating a new file on the user's machine. The file will be created with the specified content, creating any necessary parent directories.",
      parameters = {
        type = "object",
        properties = {
          filepath = {
            type = "string",
            description = "The absolute path to the file to create, including its filename and extension.",
          },
          content = {
            type = "string",
            description = "The content to write to the file.",
          },
        },
        required = {
          "filepath",
          "content",
        },
      },
    },
  },
  handlers = {
    ---@param self CodeCompanion.Tool.CreateFile
    ---@param meta { tools: CodeCompanion.Tools }
    ---@return nil
    on_exit = function(self, meta)
      log:trace("[Create File Tool] on_exit handler executed")
    end,
  },
  output = {
    ---Returns the command that will be executed
    ---@param self CodeCompanion.Tool.CreateFile
    ---@param opts { tools: CodeCompanion.Tools }
    ---@return string
    cmd_string = function(self, opts)
      return self.args.filepath
    end,

    ---@param self CodeCompanion.Tool.CreateFile
    ---@param stdout table The output from the command
    ---@param meta { tools: CodeCompanion.Tools, cmd: table }
    success = function(self, stdout, meta)
      local chat = meta.tools.chat
      local args = self.args
      local display_path = vim.fn.fnamemodify(args.filepath, ":.")

      local llm_output = fmt("Created file `%s` successfully", display_path)

      chat:add_tool_output(self, llm_output, "")
    end,

    ---@param self CodeCompanion.Tool.CreateFile
    ---@param stderr table The error output from the command
    ---@param meta { tools: CodeCompanion.Tools, cmd: table }
    error = function(self, stderr, meta)
      local chat = meta.tools.chat
      local errors = vim.iter(stderr):flatten():join("\n")
      log:debug("[Create File Tool] Error output: %s", stderr)

      local error_output = fmt([[%s]], errors)
      chat:add_tool_output(self, error_output)
    end,

    ---Rejection message back to the LLM
    ---@param self CodeCompanion.Tool.CreateFile
    ---@param meta { tools: CodeCompanion.Tools, cmd: string, opts: table }
    ---@return nil
    rejected = function(self, meta)
      local message = "The user rejected the creation of the file"
      meta = vim.tbl_extend("force", { message = message }, meta or {})
      helpers.rejected(self, meta)
    end,
  },
}
