local log = require("codecompanion.utils.log")

local fmt = string.format

---Search the current working directory for text using ripgrep
---@param action { query: string, is_regexp: boolean?, include_pattern: string? }
---@param opts table
---@return { status: "success"|"error", data: string|table }
local function grep_search(action, opts)
  opts = opts or {}
  local query = action.query

  if not query or query == "" then
    return {
      status = "error",
      data = "Query parameter is required and cannot be empty",
    }
  end

  -- Check if ripgrep is available
  if vim.fn.executable("rg") ~= 1 then
    return {
      status = "error",
      data = "ripgrep (rg) is not installed or not in PATH",
    }
  end

  local cmd = { "rg" }
  local cwd = vim.fn.getcwd()
  local max_results = opts.max_results or 100
  local is_regexp = action.is_regexp or false
  local respect_gitignore = opts.respect_gitignore
  if respect_gitignore == nil then
    respect_gitignore = opts.respect_gitignore ~= false
  end

  -- Use JSON output for structured parsing
  table.insert(cmd, "--json")
  table.insert(cmd, "--line-number")
  table.insert(cmd, "--no-heading")
  table.insert(cmd, "--with-filename")

  -- Regex vs fixed string
  if not is_regexp then
    table.insert(cmd, "--fixed-strings")
  end

  -- Case sensitivity
  table.insert(cmd, "--ignore-case")

  -- Gitignore handling
  if not respect_gitignore then
    table.insert(cmd, "--no-ignore")
  end

  -- File pattern filtering
  if action.include_pattern and action.include_pattern ~= "" then
    table.insert(cmd, "--glob")
    table.insert(cmd, action.include_pattern)
  end

  -- Limit results per file - we'll limit total results in post-processing
  table.insert(cmd, "--max-count")
  table.insert(cmd, tostring(math.min(max_results, 50)))

  -- Add the query
  table.insert(cmd, query)

  -- Add the search path
  table.insert(cmd, cwd)

  log:debug("[Grep Search Tool] Running command: %s", table.concat(cmd, " "))

  -- Execute
  local result = vim
    .system(cmd, {
      text = true,
      timeout = 30000, -- 30 second timeout
    })
    :wait()

  if result.code ~= 0 then
    local error_msg = result.stderr or "Unknown error"

    if result.code == 1 then
      -- No matches found - this is not an error for ripgrep
      return {
        status = "success",
        data = "No matches found for the query",
      }
    elseif result.code == 2 then
      log:warn("[Grep Search Tool] Invalid arguments or regex: %s", error_msg)
      return {
        status = "error",
        data = fmt("Invalid search pattern or arguments: %s", error_msg:match("^[^\n]*") or "Unknown error"),
      }
    else
      log:error("[Grep Search Tool] Command failed with code %d: %s", result.code, error_msg)
      return {
        status = "error",
        data = fmt("Search failed: %s", error_msg:match("^[^\n]*") or "Unknown error"),
      }
    end
  end

  local output = result.stdout or ""
  if output == "" then
    return {
      status = "success",
      data = "No matches found for the query",
    }
  end

  -- Parse JSON output from ripgrep
  local matches = {}
  local count = 0

  for line in output:gmatch("[^\n]+") do
    if count >= max_results then
      break
    end

    local ok, json_data = pcall(vim.json.decode, line)
    if ok and json_data.type == "match" then
      local file_path = json_data.data.path.text
      local line_number = json_data.data.line_number

      -- Convert absolute path to relative path from cwd
      local relative_path = vim.fs.relpath(cwd, file_path) or file_path

      -- Extract just the filename and directory
      local filename = vim.fn.fnamemodify(relative_path, ":t")
      local dir_path = vim.fn.fnamemodify(relative_path, ":h")

      -- Format: "filename:line directory_path"
      local match_entry = fmt("%s:%d %s", filename, line_number, dir_path == "." and "" or dir_path)
      table.insert(matches, match_entry)
      count = count + 1
    end
  end

  if #matches == 0 then
    return {
      status = "success",
      data = "No matches found for the query",
    }
  end

  return {
    status = "success",
    data = matches,
  }
end

---@class CodeCompanion.Tool.GrepSearch: CodeCompanion.Agent.Tool
return {
  name = "grep_search",
  cmds = {
    ---Execute the search commands
    ---@param self CodeCompanion.Tool.GrepSearch
    ---@param args table The arguments from the LLM's tool call
    ---@param input? any The output from the previous function call
    ---@return { status: "success"|"error", data: string|table }
    function(self, args, input)
      return grep_search(args, self.tool.opts)
    end,
  },
  schema = {
    ["function"] = {
      name = "grep_search",
      description = "Do a text search in the workspace. Use this tool when you know the exact string you're searching for.",
      parameters = {
        type = "object",
        properties = {
          query = {
            type = "string",
            description = "The pattern to search for in files in the workspace. Can be a regex or plain text pattern",
          },
          is_regexp = {
            type = "boolean",
            description = "Whether the pattern is a regex. False by default.",
          },
          include_pattern = {
            type = "string",
            description = "Search files matching this glob pattern. Will be applied to the relative path of files within the workspace.",
          },
        },
        required = {
          "query",
        },
      },
    },
    type = "function",
  },
  handlers = {
    ---@param agent CodeCompanion.Agent The tool object
    ---@return nil
    on_exit = function(agent)
      log:trace("[Grep Search Tool] on_exit handler executed")
    end,
  },
  output = {
    ---The message which is shared with the user when asking for their approval
    ---@param self CodeCompanion.Agent.Tool
    ---@param agent CodeCompanion.Agent
    ---@return nil|string
    prompt = function(self, agent)
      local args = self.args
      local query = args.query or ""
      return fmt("Perform a grep search for %s?", query)
    end,

    ---@param self CodeCompanion.Tool.GrepSearch
    ---@param agent CodeCompanion.Agent
    ---@param cmd table The command that was executed
    ---@param stdout table The output from the command
    success = function(self, agent, cmd, stdout)
      local query = self.args.query
      local chat = agent.chat
      local data = stdout[1]

      local llm_output = [[<grepSearchTool>%s

NOTE:
- The output format is {filename}:{line number} {filepath}.
- For example:
init.lua:335 lua/codecompanion/strategies/chat/agents
Refers to line 335 of the init.lua file in the lua/codecompanion/strategies/chat/agents path</grepSearchTool>]]
      local output = vim.iter(stdout):flatten():join("\n")

      if type(data) == "table" then
        -- Results were found - data is an array of file paths
        local results = #data
        local results_msg = fmt("Searched text for `%s`, %d results\n```\n%s\n```", query, results, output)
        chat:add_tool_output(self, fmt(llm_output, results_msg), results_msg)
      else
        -- No results found - data is a string message
        local no_results_msg = fmt("Searched text for `%s`, no results", query)
        chat:add_tool_output(self, fmt(llm_output, no_results_msg), no_results_msg)
      end
    end,

    ---@param self CodeCompanion.Tool.GrepSearch
    ---@param agent CodeCompanion.Agent
    ---@param cmd table
    ---@param stderr table The error output from the command
    ---@param stdout? table The output from the command
    error = function(self, agent, cmd, stderr, stdout)
      local chat = agent.chat
      local query = self.args.query
      local errors = vim.iter(stderr):flatten():join("\n")
      log:debug("[Grep Search Tool] Error output: %s", stderr)

      local error_output = fmt(
        [[Searched text for `%s`, error:
```
%s
```]],
        query,
        errors
      )
      chat:add_tool_output(self, error_output)
    end,

    ---Rejection message back to the LLM
    ---@param self CodeCompanion.Tool.GrepSearch
    ---@param agent CodeCompanion.Agent
    ---@param cmd table
    ---@return nil
    rejected = function(self, agent, cmd)
      local chat = agent.chat
      chat:add_tool_output(self, "**Grep Search Tool**: The user declined to execute")
    end,
  },
}
