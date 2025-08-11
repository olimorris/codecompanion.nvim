local completion = require("codecompanion.providers.completion")

local api = vim.api

local M = {}

---Omnifunc for codecompanion buffers
---@param findstart number 1 for finding start position, 0 for returning completions
---@param base string The text to complete (only used when findstart == 0)
---@return number|table
function M.omnifunc(findstart, base)
  if findstart == 1 then
    -- Phase 1: Find the start of the completion
    local line = api.nvim_get_current_line()
    local col = api.nvim_win_get_cursor(0)[2]

    -- Look for trigger characters (#, @, /) at the start of a word
    local before_cursor = line:sub(1, col)

    -- Find the last occurrence of a trigger character followed by word characters
    local patterns = {
      "#[%w_]*$", -- Variables: #buffer, #lsp, etc.
      "@[%w_]*$", -- Tools: @tool_name, etc.
      "/[%w_]*$", -- Slash commands: /buffer, /help, etc.
    }

    for _, pattern in ipairs(patterns) do
      local start_pos = before_cursor:find(pattern)
      if start_pos then
        return start_pos - 1 -- Return 0-based position for Vim
      end
    end

    -- No trigger found
    return -1
  else
    -- Determine what type of completion based on the trigger character
    local trigger_char = base:sub(1, 1)
    local items = {}

    if trigger_char == "#" then
      -- Variables completion
      local vars = completion.variables()
      for _, item in ipairs(vars) do
        table.insert(items, {
          word = string.format("#{%s}", item.label:sub(2)),
          abbr = item.label:sub(2),
          menu = item.detail or item.description,
          kind = "v", -- variable
          icase = 1,
        })
      end
    elseif trigger_char == "@" then
      -- Tools completion
      local tools = completion.tools()
      for _, item in ipairs(tools) do
        table.insert(items, {
          word = string.format("@{%s}", item.label:sub(2)),
          abbr = item.label:sub(2),
          menu = item.detail or item.description,
          kind = "f", -- function/tool
          icase = 1,
        })
      end
    elseif trigger_char == "/" then
      -- Slash commands completion
      local slash_cmds = completion.slash_commands()
      for _, item in ipairs(slash_cmds) do
        table.insert(items, {
          word = item.label,
          abbr = item.label:sub(2),
          menu = item.detail or item.description,
          kind = "f", -- function
          icase = 1,
          user_data = {
            command = item.label:sub(2),
            label = item.label,
            type = item.type,
            config = item.config,
            from_prompt_library = item.from_prompt_library,
          },
        })
      end
    end

    -- Filter items based on what user has typed
    local filtered_items = {}
    for _, item in ipairs(items) do
      if vim.startswith(item.abbr:lower(), base:sub(2):lower()) then
        table.insert(filtered_items, item)
      end
    end

    return filtered_items
  end
end

return M

