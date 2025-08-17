local adapters = require("codecompanion.adapters")
local client = require("codecompanion.http")
local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")

local fmt = string.format

---@class CodeCompanion.Tool.SearchWeb: CodeCompanion.Tools.Tool
return {
  name = "search_web",
  cmds = {
    ---@param self CodeCompanion.Tools The Editor tool
    ---@param args table The arguments from the LLM's tool call
    ---@param cb function Callback for asynchronous calls
    ---@return nil|{ status: "success"|"error", data: string }
    function(self, args, _, cb)
      local opts = self.tool.opts

      if not opts or not opts.adapter then
        log:error("[Search Web Tool] No adapter provided")
        return cb({ status = "error", data = "No adapter for the search_web tool" })
      end
      if not args then
        log:error("[Search Web Tool] No args provided")
        return cb({ status = "error", data = "No args for the search_web tool" })
      end

      if not args.query or args.query == "" then
        log:error("[Search Web Tool] No query provided")
        return cb({ status = "error", data = "No query provided for the search_web tool" })
      end

      args.query = string.gsub(args.query, "%f[%w_]search_web%f[^%w_]", "", 1)

      local tool_adapter = config.strategies.chat.tools.search_web.opts.adapter
      local adapter = vim.deepcopy(adapters.resolve(config.adapters[tool_adapter]))
      adapter.methods.tools.search_web.setup(adapter, opts.opts, args)

      local query = args.query

      client
        .new({
          adapter = adapter,
        })
        :request(_, {
          callback = function(err, data)
            local error_message = [[Error searching for `%s`]]
            local error_message_expanded = error_message .. "\n%s"

            if err then
              log:error("[Search Web Tool] " .. error_message, query)
              return cb({ status = "error", data = fmt(error_message_expanded, query, err) })
            end

            if data then
              local output = adapter.methods.tools.search_web.callback(adapter, data)
              if output.status == "error" then
                log:error("[Search Web Tool] " .. error_message, query)
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
      name = "search_web",
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
    ---@param self CodeCompanion.Tool.SearchWeb
    ---@param tools CodeCompanion.Tools
    ---@param cmd table The command that was executed
    ---@param stdout table The output from the command
    success = function(self, tools, cmd, stdout)
      local chat = tools.chat

      local content = vim
        .iter(stdout[1])
        :map(function(result)
          return fmt([[<attachment url="%s" title="%s">%s</attachment>]], result.url, result.title, result.content)
        end)
        :totable()
      local length = #content

      local llm_output = fmt([[%s]], table.concat(content, "\n"))
      local user_output = fmt([[Searched for `%s`, %d result(s)]], cmd.query, length)

      chat:add_tool_output(self, llm_output, user_output)
    end,

    ---@param self CodeCompanion.Tool.SearchWeb
    ---@param tools CodeCompanion.Tools
    ---@param stderr table The error output from the command
    error = function(self, tools, _, stderr, _)
      local chat = tools.chat
      local args = self.args
      log:debug("[Search Web Tool] Error output: %s", stderr)

      local error_output = fmt([[Error searching for `%s`]], args.query)

      chat:add_tool_output(self, error_output)
    end,
  },
}
