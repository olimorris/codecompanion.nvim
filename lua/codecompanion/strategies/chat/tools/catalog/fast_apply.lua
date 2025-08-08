local Path = require("plenary.path")
local adapters = require("codecompanion.adapters")
local client = require("codecompanion.http")
local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")

local fmt = string.format
local api = vim.api

---Apply code changes using Morph Fast Apply via configured adapter
---@param action {filepath: string, instructions: string, code_edit: string} The arguments from the LLM's tool call
---@param cb function Callback function for completion
---@return nil
local function apply_changes_async(action, cb)
  -- Validate required parameters
  if not action or not action.filepath or not action.instructions or not action.code_edit then
    cb({ status = "error", data = "Missing required parameters: filepath, instructions and code_edit" })
    return
  end

  local filepath = vim.fs.joinpath(vim.fn.getcwd(), action.filepath)
  local p = Path:new(filepath)
  p.filename = p:expand()

  -- Check if file exists
  if not p:exists() or not p:is_file() then
    cb({
      status = "error",
      data = fmt("Error applying changes to `%s`\nFile does not exist or is not a file", action.filepath),
    })
    return
  end

  -- Read current file content
  local content = p:read()
  if not content then
    cb({
      status = "error",
      data = fmt("Failed to read content from `%s`", action.filepath),
    })
    return
  end

  -- Build the instruction and code_edit for Morph Fast Apply format
  local instruction = vim.trim(action.instructions)
  local code_edit = vim.trim(action.code_edit)

  if instruction == "" or code_edit == "" then
    cb({ status = "error", data = "Both instructions and code_edit must be provided and non-empty" })
    return
  end

  -- Build the message for Morph Apply model in the required format:
  -- <instruction>...</instruction>
  -- <code>original code</code>
  -- <update>code_edit</update>
  local messages = {
    {
      role = "user",
      content = fmt(
        "<instruction>%s</instruction>\n<code>%s</code>\n<update>%s</update>",
        instruction,
        content,
        code_edit
      ),
    },
  }

  -- Debug: Verify messages is properly created
  log:debug("[Fast Apply Tool] Created messages table: %s", vim.inspect(messages))
  if not messages or type(messages) ~= "table" or #messages == 0 then
    cb({ status = "error", data = "Failed to create messages table for API request" })
    return
  end

  -- Resolve adapter and model from tool config (tool-level opts)
  local tool_opts = (
    config.strategies
    and config.strategies.chat
    and config.strategies.chat.tools
    and config.strategies.chat.tools.fast_apply
    and config.strategies.chat.tools.fast_apply.opts
  ) or {}

  -- Determine adapter source: tool opts adapter -> global chat adapter -> fallback
  local adapter_source = tool_opts.adapter
    or (config.strategies and config.strategies.chat and config.strategies.chat.adapter)
    or "openai_compatible"

  local ok, resolved_adapter = pcall(function()
    return adapters.resolve(adapter_source)
  end)
  if not ok or not resolved_adapter then
    cb({ status = "error", data = fmt("Adapter not found or failed to resolve: %s", tostring(adapter_source)) })
    return
  end

  -- Work on a copy of the adapter so we don't mutate global adapters
  local adapter = vim.deepcopy(resolved_adapter)

  -- If a tool-level URL is provided, inject into adapter.env so adapter:get_env_vars picks it up
  if tool_opts.url then
    adapter.env = adapter.env or {}
    adapter.env.url = tool_opts.url
  end

  -- If a tool-level API key is provided, inject into adapter.env so adapter:get_env_vars picks it up
  if tool_opts.api_key then
    adapter.env = adapter.env or {}
    adapter.env.api_key = tool_opts.api_key
  end

  -- Determine model: tool opts -> adapter default -> fallback
  local model_name = tool_opts.model
    or (adapter.schema and adapter.schema.model and adapter.schema.model.default)
    or "morph-v3-large"

  adapter.schema = adapter.schema or {}
  adapter.schema.model = adapter.schema.model or {}
  adapter.schema.model.default = model_name

  adapter.parameters = adapter.parameters or {}
  adapter.parameters.model = model_name

  -- Disable streaming for this request
  adapter.opts = adapter.opts or {}
  adapter.opts.stream = false

  -- Also disable any stream-related parameters that might interfere
  adapter.parameters.stream = false
  adapter.parameters.stream_options = nil

  -- Debug: Log the adapter configuration (avoid logging sensitive values like API keys or full URLs)
  log:debug(
    "[Fast Apply Tool] Adapter selected: %s, model=%s",
    adapter.name or adapter.formatted_name or "unknown",
    adapter.parameters.model
  )

  -- Create HTTP client with the resolved adapter
  local http_client = client.new({
    adapter = adapter,
  })

  -- Make the request using the HTTP client with correct parameters
  http_client:request({
    messages = messages, -- The HTTP client will format these through the adapter
  }, {
    callback = function(err, data)
      if err then
        log:error("[Fast Apply Tool] Error: %s", err)
        cb({
          status = "error",
          data = fmt("Request error: %s", err),
        })
        return
      end

      if data then
        log:debug("[Fast Apply Tool] Received data: %s", vim.inspect(data))

        -- Parse response - the HTTP client returns structured data
        local ok, parsed = pcall(vim.json.decode, data.body)
        if not ok then
          cb({
            status = "error",
            data = fmt("Failed to parse API response: %s", parsed),
          })
          return
        end

        -- Extract updated code from response
        if not parsed.choices or #parsed.choices == 0 then
          cb({
            status = "error",
            data = "No response received from model",
          })
          return
        end

        local choice = parsed.choices[1]
        if not choice.message or not choice.message.content then
          cb({
            status = "error",
            data = "Model response did not contain content",
          })
          return
        end

        -- Use the merged code from the Apply model as-is (trim only). The Apply API returns the
        -- final merged file contents; do not perform aggressive sanitization here.
        local updated_code = vim.trim(choice.message.content)

        -- Write updated code to file
        local write_ok, write_err = pcall(function()
          p:write(updated_code, "w")
        end)

        if not write_ok then
          cb({
            status = "error",
            data = fmt("Failed to write updated code to file: %s", write_err),
          })
          return
        end

        -- Refresh buffer if file is open
        local bufnr = vim.fn.bufnr(p.filename)
        if bufnr ~= -1 and api.nvim_buf_is_loaded(bufnr) then
          api.nvim_command("checktime " .. bufnr)
        end

        cb({
          status = "success",
          data = fmt("Successfully applied changes to `%s`", action.filepath),
        })
      end
    end,
    on_error = function(err)
      log:error("[Fast Apply Tool] Request error: %s", err)
      cb({
        status = "error",
        data = fmt("Request error: %s", err),
      })
    end,
  })
end

---@class CodeCompanion.Tool.FastApply: CodeCompanion.Tools.Tool
return {
  name = "fast_apply",
  cmds = {
    ---Execute the apply code changes command
    ---@param self CodeCompanion.Tools.Tool The Fast Apply tool
    ---@param args table The arguments from the LLM's tool call
    ---@param cb function Async callback for completion
    ---@return nil
    function(self, args, _, cb)
      -- Tools framework may pass arguments as a JSON string; ensure we pass a table to the worker
      local action = args
      if type(args) == "string" then
        local ok, decoded = pcall(vim.json.decode, args)
        if ok and type(decoded) == "table" then
          action = decoded
        end
      end

      apply_changes_async(action, cb)
    end,
  },
  schema = {
    type = "function",
    ["function"] = {
      name = "fast_apply",
      description = [[ Use this tool to make an edit to an existing file.

This will be read by a less intelligent model, which will quickly apply the edit. You should make it clear what the edit is, while also minimizing the unchanged code you write.
When writing the edit, you should specify each edit in sequence, with the special comment // ... existing code ... to represent unchanged code in between edited lines.
      
For example:

// ... existing code ...
FIRST_EDIT
// ... existing code ...
SECOND_EDIT
// ... existing code ...
THIRD_EDIT
// ... existing code ...

You should still bias towards repeating as few lines of the original file as possible to convey the change.
But, each edit should contain minimally sufficient context of unchanged lines around the code you're editing to resolve ambiguity.
DO NOT omit spans of pre-existing code (or comments) without using the // ... existing code ... comment to indicate its absence. If you omit the existing code comment, the model may inadvertently delete these lines.
If you plan on deleting a section, you must provide context before and after to delete it. If the initial code is ```code \n Block 1 \n Block 2 \n Block 3 \n code```, and you want to remove Block 2, you would output ```// ... existing code ... \n Block 1 \n  Block 3 \n // ... existing code ...```.
Make sure it is clear what the edit should be, and where it should be applied.
Make edits to a file in a single edit_file call instead of multiple edit_file calls to the same file. The apply model can handle many distinct edits at once.]],
      parameters = {
        type = "object",
        properties = {
          filepath = {
            type = "string",
            description = "The path to the file to modify",
          },
          instructions = {
            type = "string",
            description = "A single-sentence instruction describing what you're changing (first-person).",
          },
          code_edit = {
            type = "string",
            description = "Precise code edit to apply. Use // ... existing code ... for unchanged spans.",
          },
        },
        required = {
          "filepath",
          "instructions",
          "code_edit",
        },
      },
    },
  },
  handlers = {
    ---@param tools CodeCompanion.Tools The tool object
    ---@return nil
    on_exit = function(tools)
      log:trace("[Fast Apply Tool] on_exit handler executed")
    end,
  },
  output = {
    ---The message which is shared with the user when asking for their approval
    ---@param self CodeCompanion.Tools.Tool
    ---@param tools CodeCompanion.Tools
    ---@return nil|string
    prompt = function(self, tools)
      local args = self.args
      local filepath = vim.fn.fnamemodify(args.filepath, ":.")
      return fmt(
        "Apply code changes to %s using Morph Fast Apply?\n\nInstruction: %s\n\nCode edit: %s",
        filepath,
        args.instructions or "",
        args.code_edit or ""
      )
    end,

    ---@param self CodeCompanion.Tools.Tool
    ---@param tools CodeCompanion.Tools
    ---@param cmd table The command that was executed
    ---@param stdout table The output from the command
    success = function(self, tools, cmd, stdout)
      local chat = tools.chat
      local output = vim.iter(stdout):flatten():join("\n")

      chat:add_tool_output(self, output)
    end,

    ---@param self CodeCompanion.Tools.Tool
    ---@param tools CodeCompanion.Tools
    ---@param cmd table
    ---@param stderr table The error output from the command
    error = function(self, tools, cmd, stderr)
      local chat = tools.chat
      local errors = vim.iter(stderr):flatten():join("\n")
      log:debug("[Fast Apply Tool] Error output: %s", stderr)

      chat:add_tool_output(self, errors)
    end,

    ---Rejection message back to the LLM
    ---@param self CodeCompanion.Tools.Tool
    ---@param tools CodeCompanion.Tools
    ---@param cmd table
    ---@return nil
    rejected = function(self, tools, cmd)
      local chat = tools.chat
      chat:add_tool_output(self, "**Fast Apply Tool**: The user declined to execute")
    end,
  },
}
