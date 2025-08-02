local log = require("codecompanion.utils.log")

---@class CodeCompanion.AdapterArgs
return {
  name = "jina",
  opts = {
    stream = false,
  },
  url = "",
  env = {},
  headers = {},
  schema = {
    model = {
      default = "jina",
    },
  },
  handlers = {},
  methods = {
    slash_commands = {
      fetch = {
        ---@param self CodeCompanion.Adapter
        ---@param data table
        ---@return nil
        setup = function(self, data)
          self.url = "https://r.jina.ai"

          self.handlers.set_body = function()
            return { url = data.url }
          end

          self.headers = vim.tbl_deep_extend("force", self.headers, {
            ["Content-Type"] = "application/json",
            ["X-Return-Format"] = "text",
            ["Accept"] = "application/json",
          })

          if self.env and self.env.api_key then
            self.headers = vim.tbl_deep_extend("force", self.headers, {
              ["Authorization"] = "Bearer ${api_key}",
            })
          end
        end,

        ---Process the output from the fetch slash command
        ---@param self CodeCompanion.Adapter
        ---@param data table The data returned from the fetch
        ---@return table{status: string, content: string}|nil
        callback = function(self, data)
          local ok, data = pcall(vim.json.decode, data.body)
          if not ok then
            return {
              status = "error",
              content = "Could not parse JSON response",
            }
          end

          if data.code ~= 200 then
            log:error("[Jina Adapter] Error: %s", data)
            return {
              status = "error",
              content = data.message or data.body or "Unknown error occurred",
            }
          end

          return {
            status = "success",
            content = data.data.text or "",
          }
        end,
      },
    },
    tools = {
      fetch_webpage = {
        ---Setup the adapter for the fetch webpage tool
        ---@param self CodeCompanion.Adapter
        ---@param data table The data from the LLM's tool call
        ---@return nil
        setup = function(self, data)
          self.methods.slash_commands.fetch.setup(self, data)
          self.handlers.set_body = function()
            return { url = data.url }
          end
        end,

        ---Process the output from the fetch webpage tool
        ---@param self CodeCompanion.Adapter
        ---@param data table The data returned from the fetch
        ---@return table{status: string, content: string}|nil
        callback = function(self, data)
          local ok, data = pcall(vim.json.decode, data.body)
          if not ok then
            return {
              status = "error",
              output = "Failed to decode JSON content",
            }
          end
          if data.code ~= 200 then
            log:error("[Jina Adapter] Error: %s", data)
            return {
              status = "error",
              content = data.message or data.body or "Unknown error occurred",
            }
          end
          return {
            success = "success",
            content = data.data.text,
          }
        end,
      },
    },
  },
}
