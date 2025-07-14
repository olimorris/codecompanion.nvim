local adapters = require("codecompanion.adapters")
local client = require("codecompanion.http")
local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")

local fmt = string.format

---@class CodeCompanion.Tool.WebSearch: CodeCompanion.Agent.Tool
return {
  name = "web_search",
  cmds = {
    ---@param self CodeCompanion.Agent The Editor tool
    ---@param args table The arguments from the LLM's tool call
    ---@param cb function Callback for asynchronous calls
    ---@return nil|{ status: "success"|"error", data: string }
    function(self, args, _, cb)
      if not self.tool then
        log:error("There is no tool configured for the Agent")
        return cb({ status = "error" })
      end

      local opts = self.tool.opts

      if not opts then
        log:error("There is no adapter configured for the `web_search` Tool")
        return cb({ status = "error" })
      end

      if not args then
        log:error("There was no search query provided for the `web_search` Tool")
        return cb({ status = "error" })
      end

      args.query = string.gsub(args.query, "%f[%w_]web_search%f[^%w_]", "", 1)

      local tool_adapter = config.strategies.chat.tools.web_search.opts.adapter
      local adapter = adapters.resolve(config.adapters[tool_adapter])

      if not adapter then
        log:error("Failed to load the adapter for the web_search Tool")
        return cb({ status = "error" })
      end

      client
        .new({
          adapter = adapter,
        })
        :request({
          url = adapter.url,
          query = args.query,
          include_domains = args.include_domains,
        }, {
          callback = function(err, data)
            if err then
              log:error("Web Search Tool failed to fetch the URL, with error %s", err)
              return cb({ status = "error", data = "Web Search Tool failed to fetch the URL, with error " .. err })
            end

            if data then
              local http_ok, body = pcall(vim.json.decode, data.body)
              if not http_ok then
                log:error("Web Search Tool Could not parse the JSON response")
                return cb({ status = "error", data = "Web Search Tool Could not parse the JSON response" })
              end
              if data.status == 200 then
                local output = adapter.methods.tools.web_search.output(adapter, body)
                return cb({ status = "success", data = output })
              else
                log:error("Error %s - %s", data.status, body)
                return cb({ status = "error", data = fmt("Web Search Tool Error %s - %s", data.status, body) })
              end
            else
              log:error("Error no data %s - %s", data.status)
              return cb({
                status = "error",
                data = fmt("Web Search Tool Error: No data received, status %s", data and data.status or "unknown"),
              })
            end
          end,
        })
    end,
  },
  schema = {
    type = "function",
    ["function"] = {
      name = "web_search",
      description = "Search for recent information on the web",
      parameters = {
        type = "object",
        properties = {
          query = {
            type = "string",
            description = "Search query optimized for keyword searching.",
          },
          include_domains = {
            type = "array",
            items = {
              type = "string",
              description = "Each string should be a url, like `https://github.com/` or `https://neovim.io/`",
            },
            description = "When there's a specific site that you want to search from, add the url to the sites here. They must be from user input or from a previous search result. Otherwise, leave this field empty.",
          },
        },
        required = { "query", "include_domains" },
        additionalProperties = false,
      },
      strict = true,
    },
  },
  system_prompt = [[# Web Search Tool (`web_search`)

## CONTEXT
- You are connected to a Neovim instance via CodeCompanion.
- Using this tool you can search for recent information on the web.
- The user will allow this tool to be executed, so you do not need to ask for permission.

## OBJECTIVE
- Invoke this tool when up to date information is required.

## RESPONSE
- Return a single JSON-based function call matching the schema.

## POINTS TO NOTE
- This tool can be used alongside other tools within CodeCompanion.
- To make a web search, you can provide a search string optimized for keyword searching.
- Carefully craft your websearch to retrieve relevant and up to date information.
]],
  output = {
    ---@param self CodeCompanion.Tool.WebSearch
    ---@param agent CodeCompanion.Agent
    ---@param output string[][] -- The chat_output returned from the adapter will be in the first position in the table
    success = function(self, agent, cmd, output)
      local chat = agent.chat

      local length = #output
      local content = ""
      if type(output[1]) == "table" then
        content = table.concat(output[1], "")
        length = #output[1]
      end

      local query_output = fmt([[Searched for `%s`, %d results]], cmd.query, length)

      chat:add_tool_output(self, content, query_output)
    end,

    ---@param self CodeCompanion.Tool.WebSearch
    ---@param agent CodeCompanion.Agent
    ---@param stderr table The error output from the command
    error = function(self, agent, _, stderr, _)
      local chat = agent.chat
      local args = self.args
      log:debug("[Web Search Tool] Error output: %s", stderr)

      local error_output = fmt([[Error searching for `%s`]], string.upper(args.query))

      chat:add_tool_output(self, error_output)
    end,
  },
}
