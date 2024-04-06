local log = require("codecompanion.utils.log")

local function get_system_prompt(tbl)
  for i = 1, #tbl do
    if tbl[i].role == "system" then
      return i
    end
  end
end

local function merge_messages(messages)
  local new_msgs = {}
  local temp_msgs = {}
  local last_role = nil

  for _, message in ipairs(messages) do
    if message.role == "user" then
      if last_role == "user" then
        -- If the last role was also "user", we continue accumulating the content
        table.insert(temp_msgs, message.content)
      else
        -- If we encounter "user" after a different role, start a new accumulation
        temp_msgs = { message.content }
      end
    else
      -- For any non-user message:
      if last_role == "user" then
        -- If the last message was a user message, we need to insert the accumulated content first
        table.insert(new_msgs, {
          role = "user",
          content = table.concat(temp_msgs, " "),
        })
      end
      -- Insert the current non-user message
      table.insert(new_msgs, message)
    end
    last_role = message.role
  end

  -- After looping, check if the last messages were from "user" and need to be inserted
  if last_role == "user" then
    table.insert(new_msgs, {
      role = "user",
      content = table.concat(temp_msgs, " "),
    })
  end

  return new_msgs
end

---@class CodeCompanion.Adapter
---@field name string
---@field url string
---@field raw? table
---@field headers table
---@field parameters table
---@field callbacks table
---@field schema table
return {
  name = "Anthropic",
  url = "https://api.anthropic.com/v1/messages",
  env = {
    api_key = "ANTHROPIC_API_KEY",
  },
  headers = {
    ["anthropic-version"] = "2023-06-01",
    ["content-type"] = "application/json",
    ["x-api-key"] = "${api_key}",
  },
  parameters = {
    stream = true,
  },
  callbacks = {
    ---Set the parameters
    ---@param params table
    ---@param messages table
    ---@return table
    form_parameters = function(params, messages)
      -- As per: https://docs.anthropic.com/claude/docs/system-prompts
      -- Claude doesn't put the system prompt in the messages array, but in the parameters.system field
      local sys_prompt = get_system_prompt(messages)
      if sys_prompt then
        params.system = messages[sys_prompt].content
      end

      return params
    end,

    ---Set the format of the role and content for the messages from the chat buffer
    ---@param messages table Format is: { { role = "user", content = "Your prompt here" } }
    ---@return table
    form_messages = function(messages)
      -- Remove any system prompts from the messages array
      local sys_prompt = get_system_prompt(messages)
      if sys_prompt then
        table.remove(messages, sys_prompt)
      end

      -- Combine consecutive user prompts into a single prompt
      messages = merge_messages(messages)

      return { messages = messages }
    end,

    ---Has the streaming completed?
    ---@param data string The data from the format_data callback
    ---@return boolean
    is_complete = function(data)
      if data then
        data = data:sub(6)

        local ok
        ok, data = pcall(vim.fn.json_decode, data)
        if ok and data.type then
          return data.type == "message_stop"
        end
        if ok and data.delta.stop_reason then
          return data.delta.stop_reason == "end_turn"
        end
      end
      return false
    end,

    ---Output the data from the API ready for insertion into the chat buffer
    ---@param data string The streamed JSON data from the API, also formatted by the format_data callback
    ---@return table|nil
    chat_output = function(data)
      local output = {}

      -- Skip the event messages
      if type(data) == "string" and string.sub(data, 1, 6) == "event:" then
        return
      end

      if data and data ~= "" then
        data = data:sub(6)
        local ok, json = pcall(vim.json.decode, data, { luanil = { object = true } })

        if not ok then
          log:error("Malformed json: %s", json)
          return {
            status = "error",
            output = string.format("Error malformed json: %s", json),
          }
        end

        if json.type == "error" then
          return {
            status = "error",
            output = json.error.message,
          }
        end

        if json.type == "message_start" then
          output.role = json.message.role
          output.content = ""
        end

        if json.type == "content_block_delta" then
          output.role = nil
          output.content = json.delta.text
        end

        -- log:trace("----- For Adapter test creation -----\nOutput: %s\n ---------- // END ----------", output)

        return {
          status = "success",
          output = output,
        }
      end
    end,

    ---Output the data from the API ready for inlining into the current buffer
    ---@param data table The streamed JSON data from the API, also formatted by the format_data callback
    ---@param context table Useful context about the buffer to inline to
    ---@return table|nil
    inline_output = function(data, context)
      if data and data ~= "" then
        data = data:sub(6)
        local ok, json = pcall(vim.json.decode, data, { luanil = { object = true } })

        if not ok then
          return
        end

        -- log:trace("INLINE JSON: %s", json)
        if json.type == "content_block_delta" then
          return json.delta.text
        end
      end
    end,
  },
  schema = {
    model = {
      order = 1,
      mapping = "parameters",
      type = "enum",
      desc = "ID of the model to use. See the model endpoint compatibility table for details on which models work with the Chat API.",
      default = "claude-3-haiku-20240307",
      choices = {
        "claude-3-haiku-20240307",
        "claude-3-sonnet-20240229",
        "claude-3-opus-20240229",
        "claude-2.1",
      },
    },
    max_tokens = {
      order = 2,
      mapping = "parameters",
      type = "number",
      optional = true,
      default = 1024,
      desc = "The maximum number of tokens to generate in the chat completion. The total length of input tokens and generated tokens is limited by the model's context length.",
      validate = function(n)
        return n > 0, "Must be greater than 0"
      end,
    },
    temperature = {
      order = 3,
      mapping = "parameters",
      type = "number",
      optional = true,
      default = 0,
      desc = "What sampling temperature to use, between 0 and 1. Higher values like 0.8 will make the output more random, while lower values like 0.2 will make it more focused and deterministic. We generally recommend altering this or top_p but not both.",
      validate = function(n)
        return n >= 0 and n <= 1, "Must be between 0 and 1"
      end,
    },
  },
}
