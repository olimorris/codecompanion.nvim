local h = require("tests.helpers")
local adapter

local new_set = MiniTest.new_set
T = new_set()

T["Tavily adapter"] = new_set({
  hooks = {
    pre_case = function()
      adapter = require("codecompanion.adapters.tavily")
      adapter.opts = {}
    end,
  },
})

T["Tavily adapter"]["should return properly formatted body with default options"] = function()
  local data = { query = "test query", include_domains = { "https://github.com" } }
  local body = adapter.handlers.set_body(adapter, data)

  h.eq(body.query, data.query)
  h.eq(body.topic, "general")
  h.eq(body.search_depth, "advanced")
  h.eq(body.time_range, nil)
  h.eq(body.chunks_per_source, 3)
  h.eq(body.max_results, 3)
  h.eq(body.include_answer, false)
  h.eq(body.include_raw_content, false)
  h.eq(body.include_domains, { "https://github.com" })
end

T["Tavily adapter"]["should use adapter options if provided"] = function()
  adapter.opts = {
    topic = "news",
    search_depth = "basic",
    chunks_per_source = 5,
    max_results = 10,
    time_range = "week",
    include_answer = true,
    include_raw_content = true,
  }

  local data = { query = "test query" }
  local body = adapter.handlers.set_body(adapter, data)

  h.eq(body.query, data.query)
  h.eq(body.topic, "news")
  h.eq(body.search_depth, "basic")
  h.eq(body.chunks_per_source, 5)
  h.eq(body.max_results, 10)
  h.eq(body.time_range, "week")
  h.eq(body.include_answer, true)
  h.eq(body.include_raw_content, true)
end

T["Tavily adapter"]["should include days when topic is news"] = function()
  local data = {
    query = "test query",
  }

  adapter.opts.topic = "news"
  adapter.opts.days = 14

  local body = adapter.handlers.set_body(adapter, data)

  h.eq(body.query, data.query)
  h.eq(body.days, 14)
  h.eq(body.topic, "news")
end

T["Tavily adapter"]["should use default days when topic is news and days not provided"] = function()
  local data = {
    query = "test query",
  }

  adapter.opts.topic = "news"
  local body = adapter.handlers.set_body(adapter, data)

  h.eq(body.days, 7)
  h.eq(body.topic, "news")
end

T["Tavily adapter"]["should format results correctly"] = function()
  local data = {
    results = {
      { title = "Title 1", url = "https://example.com/1", content = "Content 1" },
      { title = "Title 2", url = "https://example.com/2", content = "Content 2" },
    },
  }

  local expected = {
    "**Title: Title 1**\nURL: https://example.com/1\nContent: Content 1\n\n",
    "**Title: Title 2**\nURL: https://example.com/2\nContent: Content 2\n\n",
  }

  local res = adapter.methods.tools.web_search.output(adapter, data)
  h.eq(res, expected)
end

T["Tavily adapter"]["should handle missing fields"] = function()
  local data = {
    results = {
      { url = "https://example.com/1", content = "Content 1" },
      { title = "Title 2", content = "Content 2" },
      { title = "Title 3", url = "https://example.com/3" },
    },
  }

  local expected = {
    "**Title: **\nURL: https://example.com/1\nContent: Content 1\n\n",
    "**Title: Title 2**\nURL: \nContent: Content 2\n\n",
    "**Title: Title 3**\nURL: https://example.com/3\nContent: \n\n",
  }

  local res = adapter.methods.tools.web_search.output(adapter, data)
  h.eq(res, expected)
end

return T
