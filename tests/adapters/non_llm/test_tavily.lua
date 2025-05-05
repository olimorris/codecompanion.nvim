local h = require("tests.helpers")
local new_set = MiniTest.new_set

local adapter = require("codecompanion.adapters.non_llm.tavily")
local log = require("codecompanion.utils.log")

local original_log_error

local T = new_set({
  hooks = {
    pre_case = function()
      adapter.opts = {}

      original_log_error = log.error
      log.error = function(msg)
        return msg
      end
    end,
    post_case = function()
      -- restore real log.error
      log.error = original_log_error
    end,
  },
})

T["set_body handler"] = new_set()

T["set_body handler"]["should return error when query is nil"] = function()
  local res = adapter.handlers.set_body(adapter, {})
  h.eq(type(res.error) == "function", true)
end

T["set_body handler"]["should return error when query is empty"] = function()
  local res = adapter.handlers.set_body(adapter, { query = "" })
  h.eq(type(res.error) == "function", true)
end

T["set_body handler"]["should return properly formatted body with default options"] = function()
  local data = { query = "test query" }
  local body = adapter.handlers.set_body(adapter, data)

  h.eq(body.query, data.query)
  h.eq(body.topic, "general")
  h.eq(body.search_depth, "advanced")
  h.eq(body.time_range, nil)
  h.eq(body.chunks_per_source, 3)
  h.eq(body.max_results, 3)
  h.eq(body.include_answer, false)
  h.eq(body.include_raw_content, false)
end

T["set_body handler"]["should use adapter options if provided"] = function()
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

T["set_body handler"]["should include days when topic is news"] = function()
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

T["set_body handler"]["should use default days when topic is news and days not provided"] = function()
  local data = {
    query = "test query",
  }

  adapter.opts.topic = "news"
  local body = adapter.handlers.set_body(adapter, data)

  h.eq(body.days, 7)
  h.eq(body.topic, "news")
end

T["chat_output handler"] = new_set()

T["chat_output handler"]["should return error when results are nil"] = function()
  local res = adapter.handlers.chat_output(adapter, {})
  h.eq(type(res.error) == "function", true)
end

T["chat_output handler"]["should return error when results are empty"] = function()
  local res = adapter.handlers.chat_output(adapter, { results = {} })
  h.eq(type(res.error) == "function", true)
end

T["chat_output handler"]["should format results correctly"] = function()
  local data = {
    results = {
      { title = "Title 1", url = "https://example.com/1", content = "Content 1" },
      { title = "Title 2", url = "https://example.com/2", content = "Content 2" },
    },
  }

  local expected = table.concat({
    "**Title: Title 1**\n",
    "URL: https://example.com/1\n",
    "Content: Content 1\n\n",
    "**Title: Title 2**\n",
    "URL: https://example.com/2\n",
    "Content: Content 2\n\n",
  }, "")

  local res = adapter.handlers.chat_output(adapter, data)
  h.eq(res, expected)
end

T["chat_output handler"]["should handle missing fields"] = function()
  local data = {
    results = {
      { url = "https://example.com/1", content = "Content 1" },
      { title = "Title 2", content = "Content 2" },
      { title = "Title 3", url = "https://example.com/3" },
    },
  }

  local expected = table.concat({
    "**Title: **\n",
    "URL: https://example.com/1\n",
    "Content: Content 1\n\n",
    "**Title: Title 2**\n",
    "URL: \n",
    "Content: Content 2\n\n",
    "**Title: Title 3**\n",
    "URL: https://example.com/3\n",
    "Content: \n\n",
  }, "")

  local res = adapter.handlers.chat_output(adapter, data)
  h.eq(res, expected)
end

return T
