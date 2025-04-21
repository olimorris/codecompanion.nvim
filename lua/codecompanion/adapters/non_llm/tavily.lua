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
    set_body = function(_, data)
      if data.query == nil or data.query == "" then
        return log:error("Query is required")
      end

      local body = {
        query = data.query,
        topic = data.topic or "general",
        search_depth = data.search_depth or "advanced",
        chunks_per_source = data.chunks_per_source or 3,
        max_results = data.max_results or 3,
        time_range = data.time_range or nil, -- day, week, month, year
        include_answer = data.include_answer or false,
        include_raw_content = data.include_raw_content or false,
      }

      if data.topic == "news" then
        body.days = data.days or 7
      end

      return body
    end,
    chat_output = function(_, data)
      if data.results == nil or #data.results == 0 then
        return log:error("No results found")
      end

      local output = {}
      for _, result in ipairs(data.results) do
        local title = result.title or ""
        local url = result.url or ""
        local content = result.content or ""
        table.insert(output, string.format("**Title: %s**\nURL: %s\nContent: %s\n\n", title, url, content))
      end

      return { content = table.concat(output, "") }
    end,
  },
}
