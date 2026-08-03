local Job = require("plenary.job")
local log = require("codecompanion.utils.log")

local fmt = string.format

---@class CodeCompanion.AdapterArgs
return {
  name = "markitdown",
  opts = {
    stream = false,
    ---Override the default HTTP request with a CLI-based one
    ---@param self CodeCompanion.HTTPAdapter
    ---@param _payload table
    ---@param actions { callback: fun(err: nil|table, data: nil|table) }
    ---@param _opts? table
    ---@return nil
    request = function(self, _payload, actions, _opts)
      local url = self.temp and self.temp.url

      if not url then
        return actions.callback({ message = "No URL provided" }, nil)
      end

      local ok, result = pcall(function()
        return Job:new({
          command = "markitdown",
          args = { url },
          enable_handlers = true,
        }):sync()
      end)

      if not ok then
        local err_msg = fmt("Failed to run `markitdown`: %s", tostring(result))
        log:error("[MarkItDown Adapter] %s", err_msg)
        return actions.callback({ message = err_msg }, nil)
      end

      if not result or #result == 0 then
        return actions.callback(
          { message = fmt("No content returned from `markitdown` for `%s`", url) },
          nil
        )
      end

      return actions.callback(nil, { body = table.concat(result, "\n") })
    end,
  },
  url = "",
  env = {},
  headers = {},
  schema = {
    model = {
      default = "markitdown",
    },
  },
  handlers = {},
  methods = {
    slash_commands = {
      fetch = {
        ---@param self CodeCompanion.HTTPAdapter
        ---@param data table
        ---@return nil
        setup = function(self, data)
          self.temp = self.temp or {}
          self.temp.url = data.url
        end,

        ---Process the output from the fetch slash command
        ---@param self CodeCompanion.HTTPAdapter
        ---@param data table The data returned from the fetch
        ---@return table{status: string, content: string}|nil
        callback = function(self, data)
          if not data.body or data.body == "" then
            return {
              status = "error",
              content = "No content returned",
            }
          end

          return {
            status = "success",
            content = data.body,
          }
        end,
      },
    },
    tools = {
      fetch_webpage = {
        ---Setup the adapter for the fetch webpage tool
        ---@param self CodeCompanion.HTTPAdapter
        ---@param data table The data from the LLM's tool call
        ---@return nil
        setup = function(self, data)
          self.methods.slash_commands.fetch.setup(self, data)
        end,

        ---Process the output from the fetch webpage tool
        ---@param self CodeCompanion.HTTPAdapter
        ---@param data table The data returned from the fetch
        ---@return table{status: string, content: string}|nil
        callback = function(self, data)
          if not data.body or data.body == "" then
            return {
              status = "error",
              content = "No content returned from markitdown",
            }
          end

          return {
            status = "success",
            content = data.body,
          }
        end,
      },
    },
  },
}
