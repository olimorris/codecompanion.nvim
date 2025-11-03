local adapters = require("codecompanion.adapters")
local client = require("codecompanion.http")
local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")
local utils = require("codecompanion.utils")

local fmt = string.format

---@class CodeCompanion.Tool.WebSearch: CodeCompanion.Tools.Tool
return {
  name = "web_search",
  cmds = {
    ---@param self CodeCompanion.Tools The Editor tool
    ---@param args table The arguments from the LLM's tool call
    ---@param cb function Callback for asynchronous calls
    ---@return nil|{ status: "success"|"error", data: string }
    function(self, args, _, cb)
      local opts = self.tool.opts

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

      if args.include_images then
        if self.chat.adapter.opts == nil then
          log:warn("[Web Search Tool] Disabling `include_images` because the chat adapter doesn't support vision.")
          args.include_images = nil
        elseif not self.chat.adapter.opts.vision then
          log:warn("[Web Search Tool] Disabling `include_images` because the chat adapter disabled vision.")
          args.include_images = nil
        end
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
        :request({ query = query, domains = args.domains, include_images = args.include_images }, {
          callback = function(err, data)
            local error_message = [[Error searching for `%s`]]
            local error_message_expanded = error_message .. "\n%s"

            if err then
              log:error("[Web Search Tool] " .. error_message, query)
              return cb({ status = "error", data = fmt(error_message_expanded, query, err) })
            end

            if data then
              local output = adapter.methods.tools.web_search.callback(adapter, data)
              if output.status == "error" then
                log:error("[Web Search Tool] " .. error_message, query)
                return cb({ status = "error", data = fmt(error_message_expanded, query, output.content) })
              end

              return cb({ status = "success", data = { content = output.content, images = output.images } })
            end
          end,
        })
    end,
  },
  schema = {
    type = "function",
    ["function"] = {
      name = "web_search",
      description = [[Searches the web for a given query and returns the results. 
If the tool returned image URLs, you should call the `fetch_images` tool to view the images that are relevant to the current tasks.]],
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
          include_images = {
            type = "boolean",
            description = "Whether image results are needed for this search. Enable this if the query is related to the appearance of something, like the design of a GUI application or a website. Otherwise, disable this to save tokens.",
          },
        },
        required = { "query", "domains", "include_images" },
      },
    },
  },
  output = {
    ---@param self CodeCompanion.Tool.WebSearch
    ---@param tools CodeCompanion.Tools
    ---@param cmd table The command that was executed
    ---@param stdout table The output from the command
    success = function(self, tools, cmd, stdout)
      local chat = tools.chat

      local content = vim
        .iter(stdout[1].content)
        :map(function(result)
          return fmt([[<attachment url="%s" title="%s">%s</attachment>]], result.url, result.title, result.content)
        end)
        :totable()

      ---@type string[]
      local images = vim
        .iter(utils.fix_nil(stdout[1].images) or {})
        :map(function(item)
          -- https://docs.tavily.com/documentation/api-reference/endpoint/search#response-images
          if type(item) == "string" then
            return fmt([[<attachment image_url="%s"></attachment>]], item)
          elseif type(item) == "table" then
            return fmt([[<attachment image_url="%s">%s</attachment>]], item.url, item.description)
          end
        end)
        :totable()

      local length = #content

      local llm_output = fmt([[%s]], table.concat(content, "\n"))
      local user_output = fmt([[Searched for `%s`, %d result(s)]], cmd.query, length)

      if #images > 0 then
        llm_output = llm_output .. fmt("\n%s", table.concat(images, "\n"))
        user_output = user_output .. fmt(" and %d image(s)", #images)
      end

      chat:add_tool_output(self, llm_output, user_output)
    end,

    ---@param self CodeCompanion.Tool.WebSearch
    ---@param tools CodeCompanion.Tools
    ---@param stderr table The error output from the command
    error = function(self, tools, _, stderr, _)
      local chat = tools.chat
      local args = self.args
      log:debug("[Web Search Tool] Error output: %s", stderr)

      local error_output = fmt([[Error searching for `%s`]], args.query)

      chat:add_tool_output(self, error_output)
    end,
  },
}
