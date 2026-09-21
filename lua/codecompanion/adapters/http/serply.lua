local log = require("codecompanion.utils.log")

local fmt = string.format

local time_ranges = {
  day = "d",
  week = "w",
  month = "m",
  year = "y",
}

---@class CodeCompanion.HTTPAdapter
return {
  name = "serply",
  formatted_name = "Serply",
  roles = {
    llm = "assistant",
    user = "user",
  },
  opts = {
    method = "GET",
  },
  url = "https://api.serply.io/v1/search?${params}",
  env = {
    api_key = "SERPLY_API_KEY",
  },
  headers = {
    ["X-Api-Key"] = "${api_key}",
    ["User-Agent"] = "codecompanion.nvim",
  },
  schema = {
    model = {
      default = "serply",
    },
  },
  handlers = {},
  methods = {
    tools = {
      web_search = {
        ---@param self CodeCompanion.HTTPAdapter
        ---@param opts? { max_results?: number, time_range?: string, topic?: string, gl?: string, hl?: string }
        ---@param data { query: string, domains?: string[] }
        setup = function(self, opts, data)
          opts = opts or {}

          local query = data.query
          if type(data.domains) == "table" and #data.domains > 0 then
            local sites = vim.tbl_map(function(domain)
              return "site:" .. domain
            end, data.domains)
            query = query .. " " .. table.concat(sites, " OR ")
          end

          local params = {
            "q=" .. vim.uri_encode(query),
            "num=" .. tostring(opts.max_results or 5), -- Serply returns at most 10 results per request
          }
          if time_ranges[opts.time_range] then
            table.insert(params, "tbs=qdr:" .. time_ranges[opts.time_range])
          end
          if opts.topic == "news" then
            table.insert(params, "tbm=nws")
          end
          if opts.gl then
            table.insert(params, "gl=" .. opts.gl) -- country code, e.g. "us"
          end
          if opts.hl then
            table.insert(params, "hl=" .. opts.hl) -- interface language, e.g. "en"
          end

          self.env = vim.tbl_deep_extend("force", self.env or {}, {
            params = table.concat(params, "&"),
          })
        end,

        ---Process the output from the fetch webpage tool
        ---@param self CodeCompanion.HTTPAdapter
        ---@param data { status: number, body: string }
        ---@return table{status: string, content: string}|nil
        callback = function(self, data)
          local ok, body = pcall(vim.json.decode, data.body)
          if not ok then
            log:error("[Serply Adapter] Error decoding JSON: %s", data.body)
            return {
              status = "error",
              content = "Could not parse JSON response",
            }
          end

          if data.status ~= 200 then
            return {
              status = "error",
              content = fmt("Error %s - %s", data.status, body.detail or data.body),
            }
          end

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
                content = result.description or "",
                title = result.title or "",
                url = result.link or "",
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
