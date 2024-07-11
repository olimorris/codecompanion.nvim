local log = require("codecompanion.utils.log")
local utils = require("codecompanion.utils.adapters")

---@class CodeCompanion.AdapterArgs
return {
  name = "Anthropic",
  features = {
    tokens = true,
    text = true,
    vision = true,
  },
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
      local sys_prompts = utils.get_system_prompts(messages)

      -- Merge system prompts together
      if sys_prompts and #sys_prompts > 0 then
        for _, prompt in ipairs(sys_prompts) do
          params.system = (params.system or "") .. messages[prompt].content
        end
      end

      return params
    end,

    ---Set the format of the role and content for the messages from the chat buffer
    ---@param messages table Format is: { { role = "user", content = "Your prompt here" } }
    ---@return table
    form_messages = function(messages)
      -- Remove any system prompts from the messages array
      local sys_prompt = utils.get_system_prompts(messages)
      if sys_prompt and #sys_prompt > 0 then
        -- Sort the prompts in descending order so we can remove them from the table without shifting indexes
        table.sort(sys_prompt, function(a, b)
          return a > b
        end)
        for _, prompt in ipairs(sys_prompt) do
          table.remove(messages, prompt)
        end
      end

      -- Combine consecutive user prompts into a single prompt
      return { messages = utils.merge_messages(messages) }
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

    ---Returns the number of tokens generated from the LLM
    ---@param data string The data from the LLM
    ---@return number|nil
    tokens = function(data)
      if data then
        data = data:sub(6)

        local ok
        ok, data = pcall(vim.fn.json_decode, data)

        if not ok then
          return
        end

        if data.type == "message_delta" then
          log:trace("Tokens: %s", data)
          return data.usage.output_tokens
        end
      end
    end,

    ---Output the data from the API ready for insertion into the chat buffer
    ---@param data string The streamed JSON data from the API, also formatted by the format_data callback
    ---@return table|nil
    chat_output = function(data)
      local output = {}

      -- Skip the event messages
      if type(data) == "string" and (string.sub(data, 1, 6) == "event:" or data == "data: [DONE]") then
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
      desc = "The model that will complete your prompt. See https://docs.anthropic.com/claude/docs/models-overview for additional details and options.",
      default = "claude-3-5-sonnet-20240620",
      choices = {
        "claude-3-5-sonnet-20240620",
        "claude-3-opus-20240229",
        "claude-3-haiku-20240307",
        "claude-2.1",
      },
    },
    max_tokens = {
      order = 2,
      mapping = "parameters",
      type = "number",
      optional = true,
      default = 1024,
      desc = "The maximum number of tokens to generate before stopping. This parameter only specifies the absolute maximum number of tokens to generate. Different models have different maximum values for this parameter.",
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
      desc = "Amount of randomness injected into the response. Ranges from 0.0 to 1.0. Use temperature closer to 0.0 for analytical / multiple choice, and closer to 1.0 for creative and generative tasks. Note that even with temperature of 0.0, the results will not be fully deterministic.",
      validate = function(n)
        return n >= 0 and n <= 1, "Must be between 0 and 1"
      end,
    },
  },
}
