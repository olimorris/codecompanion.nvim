local log = require("codecompanion.utils.log")

---@class CodeCompanion.Adapter
return {
  name = "tavily",
  formatted_name = "Tavily",
  roles = {
    llm = "assistant",
    user = "user",
  },
  opts = {},
  url = "https://api.tavily.com/search",
  env = {
    api_key = "TAVILY_API_KEY",
  },
  headers = {
    ["Content-Type"] = "application/json",
    ["Authorization"] = "Bearer ${api_key}",
  },
  schema = {
    model = {
      default = "tavily",
    },
  },
  handlers = {
    -- https://docs.tavily.com/documentation/api-reference/endpoint/search
    -- TODO: Move this into a separate method if we implement other Tavily endpoints
    set_body = function(adapter, data)
      if data.query == nil or data.query == "" then
        return log:error("Search query is required")
      end

      adapter.opts = adapter.opts or {}
      local body = {
        query = data.query,
        topic = adapter.opts.topic or "general", -- general, news
        search_depth = adapter.opts.search_depth or "advanced", -- basic, advanced
        chunks_per_source = adapter.opts.chunks_per_source or 3,
        max_results = adapter.opts.max_results or 3,
        time_range = adapter.opts.time_range or nil, -- day, week, month, year
        include_answer = adapter.opts.include_answer or false,
        include_raw_content = adapter.opts.include_raw_content or false,
        include_domains = data.include_domains,
      }

      if adapter.opts.topic == "news" then
        body.days = adapter.opts.days or 7
      end

      return body
    end,
  },
  methods = {
    tools = {
      web_search = {
        ---Process the output from the web search tool
        ---@param self CodeCompanion.Adapter
        ---@param data table The data returned from the web search
        ---@return table
        output = function(self, data)
          if data.results == nil or #data.results == 0 then
            log:error("No results found")
            return {}
          end

          local output = {}
          for _, result in ipairs(data.results) do
            local title = result.title or ""
            local url = result.url or ""
            local content = result.content or ""
            table.insert(output, string.format("**Title: %s**\nURL: %s\nContent: %s\n\n", title, url, content))
          end

          return output
        end,
      },
    },
  },
}
