local adapters = require("codecompanion.adapters")
local client = require("codecompanion.http")
local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")

local fmt = string.format

---@class CodeCompanion.Tool.FetchWebpage: CodeCompanion.Tools.Tool
return {
  name = "fetch_webpage",
  cmds = {
    ---Execute the fetch_webpage tool
    ---@param self CodeCompanion.Tools
    ---@param args table The arguments from the LLM's tool call
    ---@param cb function Async callback for completion
    ---@return nil
    function(self, args, _, cb)
      local opts = self.tool.opts
      local url = args.url

      if not opts or not opts.adapter then
        log:error("[Fetch Webpage Tool] No adapter set for `fetch_webpage`")
        return cb({ status = "error", data = "No adapter for `fetch_webpage`" })
      end
      if not args then
        log:error("[Fetch Webpage Tool] No args for `fetch_webpage`")
        return cb({ status = "error", data = "No args for `fetch_webpage`" })
      end

      if not url or type(url) ~= "string" or url == "" then
        return cb({ status = "error", data = fmt("No URL for `fetch_webpage`") })
      end

      local tool_adapter = config.strategies.chat.tools.fetch_webpage.opts.adapter
      local adapter = vim.deepcopy(adapters.resolve(config.adapters[tool_adapter]))
      adapter.methods.tools.fetch_webpage.setup(adapter, args)

      if not url:match("^https?://") then
        log:error("[Fetch Webpage Tool] Invalid URL: `%s`", url)
        return cb({ status = "error", data = fmt("Invalid URL: `%s`", url) })
      end

      client
        .new({
          adapter = adapter,
        })
        :request(_, {
          callback = function(err, data)
            if err then
              log:error("[Fetch Webpage Tool] Error fetching `%s`: %s", url, err)
              return cb({ status = "error", data = fmt("Error fetching `%s`\n%s", url, err) })
            end

            if data then
              local output = adapter.methods.tools.fetch_webpage.callback(adapter, data)
              if output.status == "error" then
                log:error("[Fetch Webpage Tool] Error processing data for `%s`: %s", url, output.content)
                return cb({ status = "error", data = fmt("Error processing `%s`\n%s", url, output.content) })
              end

              return cb({ status = "success", data = output.content })
            end
          end,
        })
    end,
  },
  schema = {
    type = "function",
    ["function"] = {
      name = "fetch_webpage",
      description = "Fetches the main content from a web page. You should use this tool when you think the user is looking for information from a specific webpage.",
      parameters = {
        type = "object",
        properties = {
          url = {
            type = "string",
            description = "The URL of the webpage to fetch content from",
          },
        },
        required = { "url" },
      },
    },
  },
  output = {
    ---@param self CodeCompanion.Tool.FetchWebpage
    ---@param tools CodeCompanion.Tools
    ---@param cmd table The command that was executed
    ---@param stdout table The output from the command
    success = function(self, tools, cmd, stdout)
      local args = self.args
      local chat = tools.chat

      local content
      if type(stdout) == "table" then
        if #stdout == 1 and type(stdout[1]) == "string" then
          content = stdout[1]
        elseif #stdout == 1 and type(stdout[1]) == "table" then
          -- If stdout[1] is a table, try to extract content
          local first_item = stdout[1]
          if type(first_item) == "table" and first_item.content then
            content = first_item.content
          else
            -- Fallback: convert to string representation
            content = vim.inspect(first_item)
          end
        else
          -- Multiple items or other structure
          content = vim
            .iter(stdout)
            :map(function(item)
              if type(item) == "string" then
                return item
              elseif type(item) == "table" and item.content then
                return item.content
              else
                return vim.inspect(item)
              end
            end)
            :join("\n")
        end
      else
        content = tostring(stdout)
      end

      local llm_output = fmt([[<attachment url="%s">%s</attachment>]], args.url, content)
      local user_output = fmt("Fetched content from `%s`", args.url)

      chat:add_tool_output(self, llm_output, user_output)
    end,

    ---@param self CodeCompanion.Tool.FetchWebpage
    ---@param tools CodeCompanion.Tools
    ---@param cmd table
    ---@param stderr table The error output from the command
    error = function(self, tools, cmd, stderr)
      local args = self.args
      local chat = tools.chat
      local errors = vim.iter(stderr):flatten():join("\n")
      log:debug("[Fetch Webpage Tool] Error output: %s", stderr)

      local error_output = fmt(
        [[Error fetching content from `%s`:
```txt
%s
```]],
        args.url,
        errors
      )
      chat:add_tool_output(self, error_output)
    end,
  },
}
