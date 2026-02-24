local adapters = require("codecompanion.adapters")
local client = require("codecompanion.http")
local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")

local fmt = string.format

---@class CodeCompanion.Tool.WebSearch: CodeCompanion.Tools.Tool
return {
  name = "web_search",
  cmds = {
    ---@param self CodeCompanion.Tools The Editor tool
    ---@param args table The arguments from the LLM's tool call
    ---@param opts {input: any, output_cb: fun(msg: table)}
    ---@return nil|{ status: "success"|"error", data: string }
    function(self, args, opts)
      local cb = opts.output_cb
      opts = self.tool.opts

      if not opts or not opts.adapter then
        log:error("[Web Search Tool] No adapter provided")
        return cb({ status = "error", data = "No adapter for the web_search tool" })
      end
      if not args then
        log:error("[Web Search Tool] No args provided")
        return cb({ status = "error", data = "No args for the web_search tool" })
      end

      if not args.query or args.query == "" then
        log:error("[Web Search Tool] No query provided")
        return cb({ status = "error", data = "No query provided for the web_search tool" })
      end

      args.query = string.gsub(args.query, "%f[%w_]web_search%f[^%w_]", "", 1)

      local tool_adapter = config.interactions.chat.tools.web_search.opts.adapter
      local adapter = vim.deepcopy(adapters.resolve(tool_adapter))
      adapter.methods.tools.web_search.setup(adapter, opts.opts, args)

      local query = args.query

      client
        .new({
          adapter = adapter,
        })
        :request({ query = query, domains = args.domains }, {
          callback = function(err, data)
            local error_message = [[Error searching for "%s"]]
            local error_message_expanded = error_message .. " %s"

            if data then
              local output = adapter.methods.tools.web_search.callback(adapter, data)
              if output.status == "error" then
                log:error("[Web Search Tool] " .. error_message, query)
                return cb({ status = "error", data = fmt(error_message_expanded, query, output.content) })
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
      name = "web_search",
      description = "Searches the web for a given query and returns the results.",
      parameters = {
        type = "object",
        properties = {
          query = {
            type = "string",
            description = "The query to search the web for.",
          },
          domains = {
            type = "array",
            items = {
              type = "string",
            },
            description = "An array of domains to search from. You can leave this as an empty string and the search will be performed across all domains.",
          },
        },
        required = { "query", "domains" },
      },
    },
  },
  output = {
    ---@param self CodeCompanion.Tool.WebSearch
    ---@param stdout table The output from the command
    ---@param meta { tools: CodeCompanion.Tools, cmd: table }
    success = function(self, stdout, meta)
      local chat = meta.tools.chat

      local content = vim
        .iter(stdout[1])
        :map(function(result)
          return fmt([[<attachment url="%s" title="%s">%s</attachment>]], result.url, result.title, result.content)
        end)
        :totable()
      local length = #content

      local llm_output = fmt([[%s]], table.concat(content, "\n"))
      local user_output = fmt([[Searched for `%s`, %d result(s)]], meta.cmd.query, length)

      chat:add_tool_output(self, llm_output, user_output)
    end,

    ---@param self CodeCompanion.Tool.WebSearch
    ---@param stderr table The error output from the command
    ---@param meta { tools: CodeCompanion.Tools, cmd: table }
    error = function(self, stderr, meta)
      local chat = meta.tools.chat
      local args = self.args

      local error_output = fmt([[Error searching for `%s`]], args.query)

      chat:add_tool_output(self, error_output)
    end,
  },
}
