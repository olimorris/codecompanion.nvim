local fmt = string.format

---@class CodeCompanion.HTTPAdapter
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
  handlers = {},
  methods = {
    tools = {
      search_web = {
        ---Setup the adapter for the fetch webpage tool
        ---@param self CodeCompanion.HTTPAdapter
        ---@param opts table Tool options
        ---@param data table The data from the LLM's tool call
        ---@return nil
        setup = function(self, opts, data)
          opts = opts or {}
          self.handlers.set_body = function()
            local body = {
              query = data.query,
              topic = opts.topic or "general", -- general, news
              search_depth = opts.search_depth or "advanced", -- basic, advanced
              chunks_per_source = opts.chunks_per_source or 3,
              max_results = opts.max_results or 3,
              time_range = opts.time_range or nil, -- day, week, month, year
              include_answer = opts.include_answer or false,
              include_raw_content = opts.include_raw_content or false,
              include_domains = data.domains,
            }

            if opts.topic == "news" then
              body.days = opts.days or 7
            end

            return body
          end
        end,

        ---Process the output from the fetch webpage tool
        ---@param self CodeCompanion.HTTPAdapter
        ---@param data table The data returned from the fetch
        ---@return table{status: string, content: string}|nil
        callback = function(self, data)
          local ok, body = pcall(vim.json.decode, data.body)
          if not ok then
            return {
              status = "error",
              content = "Could not parse JSON response",
            }
          end

          if data.status ~= 200 then
            return {
              status = "error",
              content = fmt("Error %s - %s", data.status, body),
            }
          end

          -- Process results (move existing output logic here)
          if body.results == nil or #body.results == 0 then
            return {
              status = "error",
              content = "No results found",
            }
          end

          local output = vim
            .iter(body.results)
            :map(function(result)
              return {
                content = result.content or "",
                title = result.title or "",
                url = result.url or "",
              }
            end)
            :totable()

          return {
            status = "success",
            content = output,
          }
        end,
      },
    },
  },
}
