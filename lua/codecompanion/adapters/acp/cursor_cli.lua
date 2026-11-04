local approval_prompt = require("codecompanion.interactions.chat.helpers.approval_prompt")
local approvals = require("codecompanion.interactions.chat.tools.approvals")
local config = require("codecompanion.config")
local helpers = require("codecompanion.adapters.acp.helpers")
local labels = require("codecompanion.interactions.chat.tools.labels")
local log = require("codecompanion.utils.log")

-- Extension methods: https://cursor.com/docs/cli/acp
local REJECTIONS = {
  ["cursor/task"] = "Subagent tasks are not supported",
  ["cursor/generate_image"] = "Image generation is not supported",
}

---Show an approval prompt with a cancel choice, cancelled if the turn ends first
---@param request CodeCompanion.ACPAdapter.AgentRequest
---@param opts { title: string, prompt?: string, name: string, choices: table[] }
---@return nil
local function request_approval(request, opts)
  table.insert(opts.choices, {
    keymap = labels.keymaps().cancel,
    label = labels.cancel,
    callback = function()
      request.respond({ outcome = { outcome = "cancelled" } })
    end,
  })

  local on_done = approval_prompt.request(request.chat, vim.tbl_extend("force", opts, { id = request.message.id }))

  request.on_cancel(function()
    on_done(labels.cancel)
    request.respond({ outcome = { outcome = "cancelled" } })
  end)
end

---Show a plan in the chat buffer and let the user accept or reject it
---@param request CodeCompanion.ACPAdapter.AgentRequest
---@return nil
local function create_plan(request)
  local params = request.message.params or {}
  local chat = request.chat

  local parts = {}
  if params.name then
    table.insert(parts, "**" .. params.name .. "**\n")
  end
  if params.plan and params.plan ~= "" then
    table.insert(parts, params.plan)
  end

  local plan_content = table.concat(parts, "\n")
  if plan_content ~= "" then
    chat:add_buf_message(
      { role = config.constants.LLM_ROLE, content = plan_content },
      { type = chat.MESSAGE_TYPES.LLM_MESSAGE }
    )
  end

  -- A plan has no side effects, and Auto mode still vets each action the agent then takes
  if approvals:get_mode(chat.bufnr) ~= "ask" then
    log:debug("[ACP::Cursor] Plan accepted by the chat's approval mode")
    return request.respond({ outcome = { outcome = "accepted" } })
  end

  local keys = labels.keymaps()
  request_approval(request, {
    title = "Plan Approval",
    prompt = "Accept this plan?",
    name = "create_plan",
    choices = {
      {
        keymap = keys.accept,
        label = labels.accept,
        callback = function()
          request.respond({ outcome = { outcome = "accepted" } })
        end,
      },
      {
        keymap = keys.reject,
        label = labels.reject,
        callback = function()
          request.respond({ outcome = { outcome = "rejected" } })
        end,
      },
    },
  })
end

---Show a question in the chat buffer and let the user pick an option
---@param request CodeCompanion.ACPAdapter.AgentRequest
---@return nil
local function ask_question(request)
  local params = request.message.params or {}
  local question = (params.questions or {})[1]

  if not question then
    return request.respond({ outcome = { outcome = "skipped", reason = "No questions provided" } })
  end

  local choices = {}
  for index, option in ipairs(question.options or {}) do
    if index > 9 then
      break
    end
    table.insert(choices, {
      keymap = tostring(index),
      label = option.label,
      callback = function()
        request.respond({
          outcome = {
            outcome = "answered",
            answers = { { questionId = question.id, selectedOptionIds = { option.id } } },
          },
        })
      end,
    })
  end

  request_approval(request, {
    title = params.title or "Question",
    prompt = question.prompt,
    name = "ask_question",
    choices = choices,
  })
end

---@class CodeCompanion.ACPAdapter.Cursor: CodeCompanion.ACPAdapter
return {
  name = "cursor_cli",
  formatted_name = "Cursor",
  type = "acp",
  roles = {
    llm = "assistant",
    user = "user",
  },
  opts = {
    vision = true,
  },
  commands = {
    default = {
      "agent",
      "acp",
    },
  },
  defaults = {
    mcpServers = {},
    timeout = 20000, -- 20 seconds
  },
  parameters = {
    protocolVersion = 1,
    clientCapabilities = {
      fs = { readTextFile = true, writeTextFile = true },
    },
    clientInfo = {
      name = "CodeCompanion.nvim",
      version = "1.0.0",
    },
  },
  handlers = {
    lifecycle = {
      ---@param self CodeCompanion.ACPAdapter
      ---@return boolean
      setup = function(self)
        return true
      end,

      ---Manually handle authentication
      ---@param self CodeCompanion.ACPAdapter
      ---@return boolean
      auth = function(self)
        -- `agent` CLI requires you to just pre-auth
        -- by running `agent login`
        return true
      end,
    },

    request = {
      build_messages = helpers.build_messages,

      ---Handle the Cursor extension methods
      ---@param self CodeCompanion.ACPAdapter
      ---@param request CodeCompanion.ACPAdapter.AgentRequest
      ---@return boolean
      agent_request = function(self, request)
        local method = request.message.method

        if method == "cursor/create_plan" and request.message.id then
          create_plan(request)
          return true
        elseif method == "cursor/ask_question" and request.message.id then
          ask_question(request)
          return true
        elseif REJECTIONS[method] then
          request.respond({ outcome = { outcome = "rejected", reason = REJECTIONS[method] } })
          return true
        elseif method == "cursor/update_todos" then
          local params = request.message.params or {}
          request.respond({ outcome = { outcome = "accepted", todos = params.todos or {} } })
          return true
        end

        return false
      end,
    },
  },
}
