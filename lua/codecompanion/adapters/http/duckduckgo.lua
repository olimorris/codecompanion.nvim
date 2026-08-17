local fmt = string.format

---@class CodeCompanion.HTTPAdapter
return {
  name = "duckduckgo",
  formatted_name = "DuckDuckGo",
  roles = {
    llm = "assistant",
    user = "user",
  },
  opts = {
    method = "POST",
  },
  url = "https://html.duckduckgo.com/html/?q=${query}",
  env = {},
  headers = {
    ["User-Agent"] = "Mozilla/5.0 (X11; Linux x86_64; rv:153.0) Gecko/20100101 Firefox/153.0",
    ["Accept"] = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    ["Accept-Language"] = "en-US,en;q=0.9",
    ["Accept-Encoding"] = "gzip, deflate, br, zstd",
    ["Connection"] = "keep-alive",
    ["Upgrade-Insecure-Requests"] = "1",
    ["Sec-Fetch-Dest"] = "document",
    ["Sec-Fetch-Mode"] = "navigate",
    ["Sec-Fetch-Site"] = "none",
    ["Sec-Fetch-User"] = "?1",
    ["Priority"] = "u=0, i",
    ["TE"] = "trailers",
  },
  schema = {
    model = {
      default = "duckduckgo",
    },
  },
  handlers = {},
  methods = {
    tools = {
      web_search = {
        ---Setup the adapter for the fetch webpage tool
        ---@param self CodeCompanion.HTTPAdapter
        ---@param opts table Tool options
        ---@param data table The data from the LLM's tool call
        ---@return nil
        setup = function(self, opts, data)
          self.env = vim.tbl_deep_extend("force", self.env or {}, {
            query = vim.uri_encode(data.query),
          })
        end,

        ---Process the output from the fetch webpage tool
        ---@param self CodeCompanion.HTTPAdapter
        ---@param data table The data returned from the fetch
        ---@return table{status: string, content: string}|nil
        callback = function(self, data)
          if data.status >= 300 then
            return {
              status = "error",
              content = fmt("Error %s", data.status),
            }
          end
          local function clean_html(html)
            return html:gsub("</?b[^>]*>", ""):gsub("<[^>]+>", " "):gsub("%s+", " "):gsub("^%s*(.-)%s*$", "%1")
          end
          local out = {}
          for href, title, content in
            data.body:gmatch(
              '<a[^>]*class="[^"]*result__a[^"]*"[^>]*href="([^"]*)"[^>]*>(.-)</a>.-'
                .. '<a[^>]*class="[^"]*result__snippet[^"]*"[^>]*href="[^"]*"[^>]*>(.-)</a>'
            )
          do
            table.insert(out, {
              title = clean_html(title),
              url = href,
              content = clean_html(content),
            })
          end
          if #out < 1 and data.body:find("challenge-form", 1, true) then
            return {
              status = "error",
              content = data.body:find("challenge-form", 1, true) and "Engine thinks you're a bot"
                or "No results found",
            }
          end
          return {
            status = "success",
            content = out,
          }
        end,
      },
    },
  },
}
