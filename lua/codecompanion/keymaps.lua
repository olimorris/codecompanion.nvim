local config = require("codecompanion").config
local ts = require("codecompanion.utils.ts")
local api = vim.api

local M = {}

---Clear a keymap from a specific buffer
---@param keys string
---@param bufnr? integer
local function clear_map(keys, bufnr)
  bufnr = bufnr or 0
  vim.keymap.del("n", keys, { buffer = bufnr })
end

M.save = {
  desc = "Save the chat buffer and trigger the API",
  callback = function()
    vim.cmd("w")
  end,
}

M.close = {
  desc = "Close the chat window",
  callback = function(chat)
    chat:close()
  end,
}

M.stop = {
  desc = "Stop the current request",
  callback = function(chat)
    if chat.current_request then
      chat:stop()
    end
  end,
}

M.save_chat = {
  desc = "Save the current chat",
  callback = function(chat)
    local saved_chat = require("codecompanion.strategies.saved_chats").new({})

    if chat.saved_chat then
      saved_chat.filename = chat.saved_chat
      saved_chat:save(chat.bufnr, chat:get_messages())

      if config.silence_notifications then
        return
      end

      return vim.notify("[CodeCompanion.nvim]\nChat has been saved", vim.log.levels.INFO)
    end

    vim.ui.input({ prompt = "Chat Name" }, function(filename)
      if not filename then
        return
      end
      saved_chat.filename = filename
      saved_chat:save(chat.bufnr, chat:get_messages())
      chat.saved_chat = filename
    end)
  end,
}

M.clear = {
  desc = "Clear the current chat",
  callback = function(args)
    local ns_id = api.nvim_create_namespace("CodeCompanionTokens")
    api.nvim_buf_clear_namespace(args.bufnr, ns_id, 0, -1)

    api.nvim_buf_set_lines(args.bufnr, 0, -1, false, {})
  end,
}

M.codeblock = {
  desc = "Insert a codeblock",
  callback = function(args)
    local bufnr = api.nvim_get_current_buf()
    local cursor_pos = api.nvim_win_get_cursor(0)
    local line = cursor_pos[1]

    args.type = args.type or ""

    local codeblock = {
      "```" .. args.type,
      "",
      "```",
    }

    api.nvim_buf_set_lines(bufnr, line - 1, line, false, codeblock)
    api.nvim_win_set_cursor(0, { line + 1, vim.fn.indent(line) })
  end,
}

M.next = {
  desc = "Go to the next message",
  callback = function()
    ts.goto_heading("next", 1)
  end,
}

M.previous = {
  desc = "Go to the previous message",
  callback = function()
    ts.goto_heading("prev", 1)
  end,
}

M.add_agent = {
  desc = "Add a agent to the chat buffer",
  callback = function(chat)
    local items = {}
    for id, agent in pairs(config.agents) do
      if agent.enabled then
        table.insert(items, {
          id = id,
          name = agent.name,
          description = agent.description,
          location = agent.location,
        })
      end
    end

    if #items == 0 then
      return vim.notify("[CodeCompanion.nvim]\nNo agents available", vim.log.levels.WARN)
    end

    -- Picker of available agents
    require("codecompanion.utils.ui").selector(items, {
      prompt = "Select an agent",
      width = config.display.action_palette.width,
      height = config.display.action_palette.height,
      format = function(item)
        return {
          item.name,
          "agents",
          item.description,
        }
      end,
      callback = function(item)
        local location = item.location or "codecompanion.agents"
        local agents = require(location .. "." .. item.id)

        -- Parse the buffer to determine where to insert the prompt
        local insert_at = 0
        if config.display.chat.show_settings then
          local yaml_query = [[(block_mapping_pair key: (_) @key)]]
          local parser = vim.treesitter.get_parser(chat.bufnr, "yaml")
          local query = vim.treesitter.query.parse("yaml", yaml_query)
          local root = parser:parse()[1]:root()

          local captures = {}
          for k, v in pairs(query.captures) do
            captures[v] = k
          end

          local settings = {}
          for _, match in query:iter_matches(root, chat.bufnr) do
            local key = vim.treesitter.get_node_text(match[captures.key], chat.bufnr)
            table.insert(settings, key)
          end

          insert_at = #settings + 2
        end

        for _, prompt in ipairs(agents.prompts) do
          local content
          if type(prompt.content) == "function" then
            content = prompt.content(agents.schema)
          else
            content = prompt.content
          end

          if prompt.role == "system" then
            chat:add_message({
              role = "system",
              content = content,
            }, {
              insert_at = insert_at,
              force_role = true,
              notify = "The Code Runner agent was added to the chat buffer",
            })
          else
            chat:append({
              role = prompt.role,
              content = content,
            })
          end
        end
      end,
    })
  end,
}

M.clear_diff = {
  desc = "Clear the inline diff extmarks",
  callback = function(inline)
    local ns_id = vim.api.nvim_create_namespace("codecompanion_diff_removed_")
    api.nvim_buf_clear_namespace(inline.context.bufnr, ns_id, 0, -1)

    clear_map(inline.mapping, inline.context.bufnr)
  end,
}

return M
