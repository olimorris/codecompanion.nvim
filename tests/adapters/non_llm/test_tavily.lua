local assert = require("luassert")
local h = require("tests.helpers")
local log = require("codecompanion.utils.log")
local match = require("luassert.match")
local spy = require("luassert.spy")
local tavily_adapter = require("codecompanion.adapters.non_llm.tavily")

local original_log_error = log.error
local mock_log_error = function(_, msg)
  return msg
end

describe("Tavily adapter", function()
  local log_error_spy

  before_each(function()
    tavily_adapter.opts = {}

    log.error = mock_log_error
    log_error_spy = spy.on(log, "error")
  end)

  after_each(function()
    log.error = original_log_error
  end)

  describe("set_body handler", function()
    it("should return error when query is nil", function()
      local result = tavily_adapter.handlers.set_body(tavily_adapter, {})
      assert.spy(log_error_spy).was.called_with(log, match.is_string())
      assert.is.string(result)
    end)

    it("should return error when query is empty", function()
      local result = tavily_adapter.handlers.set_body(tavily_adapter, { query = "" })
      assert.spy(log_error_spy).was.called_with(match._, match.is_string())
      assert.is.string(result)
    end)

    it("should return properly formatted body with default options", function()
      local data = { query = "test query" }
      local body = tavily_adapter.handlers.set_body(tavily_adapter, data)

      h.eq(body.query, data.query)
      h.eq(body.topic, "general")
      h.eq(body.search_depth, "advanced")
      h.eq(body.time_range, nil)
    end)

    it("should use adapter options if provided", function()
      tavily_adapter.opts = {
        topic = "news",
        search_depth = "basic",
        chunks_per_source = 5,
        max_results = 10,
        time_range = "week",
        include_answer = true,
        include_raw_content = true,
      }

      local data = { query = "test query" }
      local body = tavily_adapter.handlers.set_body(tavily_adapter, data)

      h.eq(body.query, data.query)
      h.eq(body.topic, "news")
      h.eq(body.search_depth, "basic")
      h.eq(body.chunks_per_source, 5)
      h.eq(body.max_results, 10)
      h.eq(body.time_range, "week")
      h.eq(body.include_answer, true)
      h.eq(body.include_raw_content, true)
    end)

    it("should include days when topic is news", function()
      local data = {
        query = "test query",
        topic = "news",
        days = 14,
      }
      local body = tavily_adapter.handlers.set_body(tavily_adapter, data)

      h.eq(body.days, 14)
    end)
  end)

  describe("chat_output handler", function()
    it("should return error when results are nil", function()
      local result = tavily_adapter.handlers.chat_output(tavily_adapter, {})
      assert.spy(log_error_spy).was.called_with(log, match.is_string())
      assert.is.string(result)
    end)

    it("should return error when results are empty", function()
      local result = tavily_adapter.handlers.chat_output(tavily_adapter, { results = {} })
      assert.spy(log_error_spy).was.called_with(log, match.is_string())
      assert.is.string(result)
    end)

    it("should format results correctly", function()
      local data = {
        results = {
          {
            title = "Title 1",
            url = "https://example.com/1",
            content = "Content 1",
          },
          {
            title = "Title 2",
            url = "https://example.com/2",
            content = "Content 2",
          },
        },
      }

      local expected_output = {
        content = "**Title: Title 1**\nURL: https://example.com/1\nContent: Content 1\n\n"
          .. "**Title: Title 2**\nURL: https://example.com/2\nContent: Content 2\n\n",
      }

      local result = tavily_adapter.handlers.chat_output(tavily_adapter, data)
      h.eq(expected_output, result)
    end)

    it("should handle missing fields", function()
      local data = {
        results = {
          {
            url = "https://example.com/1",
            content = "Content 1",
          },
          {
            title = "Title 2",
            content = "Content 2",
          },
          {
            title = "Title 3",
            url = "https://example.com/3",
          },
        },
      }

      local expected_output = {
        content = "**Title: **\nURL: https://example.com/1\nContent: Content 1\n\n"
          .. "**Title: Title 2**\nURL: \nContent: Content 2\n\n"
          .. "**Title: Title 3**\nURL: https://example.com/3\nContent: \n\n",
      }

      local result = tavily_adapter.handlers.chat_output(tavily_adapter, data)
      h.eq(expected_output, result)
    end)
  end)
end)
