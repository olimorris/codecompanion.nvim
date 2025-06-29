local log = require("codecompanion.utils.log")

local fmt = string.format

---Search the current working directory for files matching the glob pattern.
---@param action { query: string, max_results: number }
---@param opts table
---@return { status: "success"|"error", data: string }
local function search(action, opts)
  opts = opts or {}
  local query = action.query

  local max_results = action.max_results or opts.max_results or 500 -- Default limit to prevent overwhelming results

  if not query or query == "" then
    return {
      status = "error",
      data = "Query parameter is required and cannot be empty",
    }
  end

  local cwd = vim.fn.getcwd()

  -- Convert glob pattern to lpeg pattern for matching
  local ok, glob_pattern = pcall(vim.glob.to_lpeg, query)
  if not ok then
    return {
      status = "error",
      data = fmt("Invalid glob pattern '%s': %s", query, glob_pattern),
    }
  end

  -- Use vim.fs.find with a custom function that matches the glob pattern
  local found_files = vim.fs.find(function(name, path)
    local full_path = vim.fs.joinpath(path, name)
    local relative_path = vim.fs.relpath(cwd, full_path)

    if not relative_path then
      return false
    end

    return glob_pattern:match(relative_path) ~= nil
  end, {
    limit = max_results,
    type = "file",
    path = cwd,
  })

  if #found_files == 0 then
    return {
      status = "success",
      data = fmt("No files found matching pattern '%s'", query),
    }
  end

  -- Convert absolute paths to relative paths so the LLM doesn't have full knowledge of the filesystem
  local relative_files = {}
  for _, file in ipairs(found_files) do
    local rel_path = vim.fs.relpath(cwd, file)
    if rel_path then
      table.insert(relative_files, rel_path)
    else
      table.insert(relative_files, file)
    end
  end

  return {
    status = "success",
    data = relative_files,
  }
end

---@class CodeCompanion.Tool.FileSearch: CodeCompanion.Agent.Tool
return {
  name = "file_search",
  cmds = {
    ---Execute the search commands
    ---@param self CodeCompanion.Tool.FileSearch
    ---@param args table The arguments from the LLM's tool call
    ---@param input? any The output from the previous function call
    ---@return { status: "success"|"error", data: string }
    function(self, args, input)
      return search(args, self.tool.opts)
    end,
  },
  schema = {
    type = "function",
    ["function"] = {
      name = "file_search",
      description = "Search for files in the workspace by glob pattern. This only returns the paths of matching files. Use this tool when you know the exact filename pattern of the files you're searching for. Glob patterns match from the root of the workspace folder. Examples:\n- **/*.{js,ts} to match all js/ts files in the workspace.\n- src/** to match all files under the top-level src folder.\n- **/foo/**/*.js to match all js files under any foo folder in the workspace.",
      parameters = {
        type = "object",
        properties = {
          query = {
            type = "string",
            description = "Search for files with names or paths matching this glob pattern.",
          },
          max_results = {
            type = "number",
            description = "The maximum number of results to return. Do not use this unless necessary, it can slow things down. By default, only some matches are returned. If you use this and don't see what you're looking for, you can try again with a more specific query or a larger max_results.",
          },
        },
        required = {
          "query",
        },
      },
    },
  },
  handlers = {
    ---@param agent CodeCompanion.Agent The tool object
    ---@return nil
    on_exit = function(agent)
      log:trace("[File Search Tool] on_exit handler executed")
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
      return fmt("Search the cwd for %s?", query)
    end,

    ---@param self CodeCompanion.Tool.FileSearch
    ---@param agent CodeCompanion.Agent
    ---@param cmd table The command that was executed
    ---@param stdout table The output from the command
    success = function(self, agent, cmd, stdout)
      local chat = agent.chat
      local query = self.args.query
      local data = stdout[1]

      local llm_output = "<fileSearchTool>%s</fileSearchTool>"
      local output = vim.iter(stdout):flatten():join("\n")

      if type(data) == "table" then
        -- Files were found - data is an array of file paths
        local files = #data
        local results_msg = fmt("Searched files for `%s`, %d results\n```\n%s\n```", query, files, output)
        chat:add_tool_output(self, fmt(llm_output, results_msg), results_msg)
      else
        -- No files found - data is a string message
        local no_results_msg = fmt("Searched files for `%s`, no results", query)
        chat:add_tool_output(self, fmt(llm_output, no_results_msg), no_results_msg)
      end
    end,

    ---@param self CodeCompanion.Tool.FileSearch
    ---@param agent CodeCompanion.Agent
    ---@param cmd table
    ---@param stderr table The error output from the command
    ---@param stdout? table The output from the command
    error = function(self, agent, cmd, stderr, stdout)
      local chat = agent.chat
      local query = self.args.query
      local errors = vim.iter(stderr):flatten():join("\n")
      log:debug("[File Search Tool] Error output: %s", stderr)

      local error_output = fmt(
        [[Searched files for `%s`, error:

```txt
%s
```]],
        query,
        errors
      )
      chat:add_tool_output(self, error_output)
    end,

    ---Rejection message back to the LLM
    ---@param self CodeCompanion.Tool.FileSearch
    ---@param agent CodeCompanion.Agent
    ---@param cmd table
    ---@return nil
    rejected = function(self, agent, cmd)
      local chat = agent.chat
      chat:add_tool_output(self, "**File Search Tool**: The user declined to execute")
    end,
  },
}
