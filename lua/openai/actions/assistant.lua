local log = require("openai.utils.log")
local schema = require("openai.schema")

---@class openai.Assistant
---@field context table
---@field is_visual boolean
---@field client openai.Client
local Assistant = {}

---@class openai.ChatEditArgs
---@field context table
---@field is_visual boolean
---@field client openai.Client

---@param opts openai.ChatEditArgs
---@return openai.Assistant
function Assistant.new(opts)
  log:trace("Initiating Assistant")

  local self = setmetatable({
    context = opts.context,
    is_visual = (opts.context.mode:match("^[vV]") == "V"),
    client = opts.client,
  }, { __index = Assistant })
  return self
end

---@param on_complete nil|fun()
function Assistant:start(on_complete)
  vim.ui.input(
    { prompt = string.gsub(self.context.filetype, "^%l", string.upper) .. " Prompt" },
    function(prompt)
      if not prompt then
        return
      end

      local config = schema.static.assistant_settings

      local settings = {
        model = config.model.default,
        messages = {
          {
            role = "assistant",
            content = string.format(
              config.prompts.choices[config.prompts.default],
              self.context.filetype
            ),
          },
          {
            role = "user",
            content = prompt,
          },
        },
      }

      if self.is_visual then
        table.insert(settings.messages, 2, {
          role = "user",
          content = "For context, this is the code I will ask you to help me with:\n"
            .. table.concat(self.context.lines, "\n"),
        })
      end

      vim.bo[self.context.bufnr].modifiable = false
      self.client:assistant(settings, function(err, data)
        if err then
          log:error("Assistant Error: %s", err)
        end

        vim.bo[self.context.bufnr].modifiable = true

        if err then
          vim.notify(err, vim.log.levels.ERROR)
          return
        end

        local new_lines = vim.split(data.choices[1].message.content, "\n")

        if self.is_visual then
          vim.api.nvim_buf_set_text(
            self.context.bufnr,
            self.context.start_row - 1,
            self.context.start_col - 1,
            self.context.end_row - 1,
            self.context.end_col,
            new_lines
          )
        else
          vim.api.nvim_buf_set_lines(
            self.context.bufnr,
            self.context.cursor_pos[1] - 1,
            self.context.cursor_pos[1] - 1,
            true,
            new_lines
          )
        end

        if on_complete then
          on_complete()
        end
      end)
    end
  )
end

return Assistant
