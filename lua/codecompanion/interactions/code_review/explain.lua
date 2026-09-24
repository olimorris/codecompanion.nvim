local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")
local store = require("codecompanion.interactions.code_review.store")
local utils = require("codecompanion.utils")

local api = vim.api
local fmt = string.format

---@class CodeCompanion.CodeReview.Channel
---@field kind "chat"|"cli"|"terminal"|"adapter"
---@field bufnr? number

local AGENT_PROMPT = "Explain the change you made at `%s:%d-%d` in this repository: what it does and why, in a few sentences. "
  .. "Write the explanation to `%s` under the heading `## %s:%d-%d`, appending after any sections already there, and edit nothing else."

local MODEL_PROMPT =
  "Explain what this change to `%s` does, in a few sentences. Do not speculate about why it was made.\n\n%s"

local M = {}

-- The agent the user picked for a repo, kept for the session because buffer numbers mean nothing to another instance
local chosen = {}

---@param message string
---@param level? number
---@return nil
local function notify(message, level)
  return utils.notify(message, level or vim.log.levels.INFO, { title = "CodeCompanion Code Review" })
end

---@param channel CodeCompanion.CodeReview.Channel
---@return boolean
local function is_live(channel)
  if channel.kind == "adapter" then
    return true
  end
  return channel.bufnr ~= nil and api.nvim_buf_is_valid(channel.bufnr)
end

---@param bufnr number
---@return string
local function describe_terminal(bufnr)
  local cli = require("codecompanion.interactions.cli").buf_get_cli(bufnr)
  if cli then
    return fmt("CodeCompanion CLI: %s", cli.agent_name)
  end
  return fmt("Terminal: %s", vim.fn.fnamemodify(api.nvim_buf_get_name(bufnr), ":t"))
end

---Ask the user which agent should explain, when the round did not record one this instance can reach
---@param root string
---@param on_resolved fun(channel: CodeCompanion.CodeReview.Channel): nil
---@return nil
local function pick_channel(root, on_resolved)
  local choices = {}
  for _, bufnr in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_is_loaded(bufnr) and vim.bo[bufnr].buftype == "terminal" then
      local cli = require("codecompanion.interactions.cli").buf_get_cli(bufnr)
      table.insert(choices, {
        label = describe_terminal(bufnr),
        channel = { kind = cli and "cli" or "terminal", bufnr = bufnr },
      })
    end
  end
  table.insert(choices, {
    label = fmt(
      "A fresh model (%s), which can say what the code does but not why",
      config.interactions.background.adapter
    ),
    channel = { kind = "adapter" },
  })

  vim.ui.select(choices, {
    prompt = "Who should explain this change?",
    format_item = function(choice)
      return choice.label
    end,
  }, function(choice)
    if not choice then
      return
    end
    chosen[root] = choice.channel
    on_resolved(choice.channel)
  end)
end

---@param root string
---@param on_resolved fun(channel: CodeCompanion.CodeReview.Channel): nil
---@return nil
local function resolve_channel(root, on_resolved)
  local channel = chosen[root] or store.round_channel(root)
  if channel and is_live(channel) then
    return on_resolved(channel)
  end
  pick_channel(root, on_resolved)
end

---@class CodeCompanion.CodeReview.Ask
---@field root string
---@field path string
---@field first number First working line of the change
---@field last number Last working line of the change
---@field snippet string The change as `-`/`+` lines with the code around it, for a model with no repository

---Have a model with no agent context describe the change, writing its answer where an agent would
---@param ask CodeCompanion.CodeReview.Ask
---@param on_done fun(ok: boolean): nil
---@return nil
local function ask_fresh_model(ask, on_done)
  local background = require("codecompanion.interactions.background").new({})
  if not background then
    notify("No adapter available to explain the change", vim.log.levels.WARN)
    return on_done(false)
  end

  background:ask({ { role = config.constants.USER_ROLE, content = fmt(MODEL_PROMPT, ask.path, ask.snippet) } }, {
    on_done = vim.schedule_wrap(function(result)
      local content = result and result.output and result.output.content
      if not content or vim.trim(content) == "" then
        notify("The model returned no explanation", vim.log.levels.WARN)
        return on_done(false)
      end
      store.add_explanation(ask.root, {
        path = ask.path,
        start_line = ask.first,
        end_line = ask.last,
        code = "",
        comment = vim.trim(content),
      })
      on_done(true)
    end),
    on_error = vim.schedule_wrap(function(err)
      log:error("[Code Review] Could not explain the change: %s", vim.inspect(err))
      on_done(false)
    end),
  })
end

---Put the question to the agent that made the change
---@param channel CodeCompanion.CodeReview.Channel
---@param ask CodeCompanion.CodeReview.Ask
---@return boolean sent
local function send_to_agent(channel, ask)
  local path = store.explanations_path(ask.root)
  local prompt = fmt(AGENT_PROMPT, ask.path, ask.first, ask.last, path, ask.path, ask.first, ask.last)

  if channel.kind == "chat" then
    local chat = require("codecompanion").buf_get_chat(channel.bufnr)
    if not chat then
      return false
    end
    if chat.current_request then
      notify("The chat is still answering; ask again when it has finished", vim.log.levels.WARN)
      return true
    end
    chat:add_buf_message({ role = config.constants.USER_ROLE, content = prompt })
    chat:submit()
    return true
  end

  if channel.kind == "cli" then
    local cli = require("codecompanion.interactions.cli").buf_get_cli(channel.bufnr)
    if not cli then
      return false
    end
    cli:send(prompt, { submit = true })
    return true
  end

  local job = vim.bo[channel.bufnr].channel
  if job == 0 then
    return false
  end
  -- A carriage return is what Enter sends down a pty, so the agent's prompt submits
  api.nvim_chan_send(job, prompt .. "\r")
  return true
end

---Ask for an explanation of a change, from the agent that made it or a fresh model as a last resort
---@param ask CodeCompanion.CodeReview.Ask
---@param opts { on_asked: fun(): nil, on_done: fun(ok: boolean): nil }
---@return nil
function M.ask(ask, opts)
  resolve_channel(ask.root, function(channel)
    if channel.kind == "adapter" then
      opts.on_asked()
      return ask_fresh_model(ask, opts.on_done)
    end

    if send_to_agent(channel, ask) then
      return opts.on_asked()
    end

    -- The agent has gone; forget it so the next ask offers a choice again
    chosen[ask.root] = nil
    notify("The agent that made this change is no longer running", vim.log.levels.WARN)
  end)
end

return M
