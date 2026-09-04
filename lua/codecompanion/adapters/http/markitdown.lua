local log = require("codecompanion.utils.log")

local fmt = string.format

---@class CodeCompanion.AdapterArgs
return {
  name = "markitdown",
  formatted_name = "MarkItDown",
  opts = {
    stream = false,
    timeout = 120000, -- Timeout for the conversion (milliseconds)
    ---Override the default HTTP request with a CLI-based one
    ---@param self CodeCompanion.HTTPClient
    ---@param _payload table
    ---@param actions { callback: fun(err: nil|table, data: nil|table) }
    ---@param _opts? table
    ---@return vim.SystemObj|nil
    request = function(self, _payload, actions, _opts)
      local url = self.adapter.env.url
      if not url then
        return actions.callback({ message = "No URL provided" }, nil)
      end

      local timeout = self.adapter.opts.timeout

      local function fail(message)
        log:error("[MarkItDown Adapter] %s", message)
        actions.callback({ message = message }, nil)
      end

      local ok, job = pcall(vim.system, { "markitdown", url }, { text = true, timeout = timeout }, function(result)
        self.methods.schedule(function()
          if result.code == 124 then
            return fail(fmt("`markitdown` timed out after %dms", timeout))
          end
          if result.code ~= 0 then
            return fail(fmt("Failed to run `markitdown` (exit %d): %s", result.code, result.stderr or ""))
          end
          actions.callback(nil, { body = result.stdout })
        end)
      end)

      if not ok then
        return fail(fmt("Failed to run `markitdown`: %s", job))
      end

      return job
    end,
  },
  env = {},
  schema = {
    model = {
      default = "markitdown",
    },
  },
  methods = {
    slash_commands = {
      fetch = {
        ---Setup the adapter for the fetch slash command
        ---@param self CodeCompanion.HTTPAdapter
        ---@param data table
        ---@return nil
        setup = function(self, data)
          self.env = vim.tbl_deep_extend("force", self.env, {
            url = data.url,
          })
        end,

        ---Process the output from the fetch slash command
        ---@param self CodeCompanion.HTTPAdapter
        ---@param data table The data returned from the fetch
        ---@return table{status: string, content: string}|nil
        callback = function(self, data)
          if not data.body or data.body == "" then
            return { status = "error", content = "No content returned" }
          end
          return { status = "success", content = data.body }
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
          self.env = vim.tbl_deep_extend("force", self.env, {
            url = data.url,
          })
        end,

        ---Process the output from the fetch webpage tool
        ---@param self CodeCompanion.HTTPAdapter
        ---@param data table The data returned from the fetch
        ---@return table{status: string, content: string}|nil
        callback = function(self, data)
          if not data.body or data.body == "" then
            return { status = "error", content = "No content returned" }
          end
          return { status = "success", content = data.body }
        end,
      },
    },
  },
}
