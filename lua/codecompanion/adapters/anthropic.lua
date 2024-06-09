local log = require("codecompanion.utils.log")

---Get the indexes of all of the system prompts in the chat buffer
---@param messages table
---@return table|nil
local function get_system_prompts(messages)
  local prompts = {}
  for i = 1, #messages do
    if messages[i].role == "system" then
      table.insert(prompts, i)
    end
  end

  if #prompts > 0 then
    return prompts
  end
end

---Takes multiple user messages and merges them into a single message
---@param messages table
---@return table
local function merge_messages(messages)
  local new_msgs = {}
  local temp_msgs = {}
  local last_role = nil

  local function trim_newlines(message)
    return (message:gsub("^%s*\n\n", ""))
  end

  for _, message in ipairs(messages) do
    if message.role == "user" then
      if last_role == "user" then
        -- If the last role was also "user", we continue accumulating the content
        table.insert(temp_msgs, trim_newlines(message.content))
      else
        -- If we encounter "user" after a different role, start a new accumulation
        temp_msgs = { trim_newlines(message.content) }
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

---@class CodeCompanion.AdapterArgs
return {
  name = "Anthropic",
  features = {
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
  chat_prompt = [[
You are an AI programming assistant. When asked for your name, you must respond with "CodeCompanion". You were built by Oli Morris. Follow the user's requirements carefully & to the letter. Your expertise is strictly limited to software development topics. Avoid content that violates copyrights. For questions not related to software development, simply give a reminder that you are an AI programming assistant. Keep your answers short and impersonal.

You can answer general programming questions and perform the following tasks:
- Ask a question about the files in your current workspace
- Explain how the selected code works
- Generate unit tests for the selected code
- Propose a fix for the problems in the selected code
- Scaffold code for a new feature
- Ask questions about Neovim
- Ask how to do something in the terminal

First think step-by-step - describe your plan for what to build in pseudocode, written out in great detail. Then output the code in a single code block. Minimize any other prose. Use Markdown formatting in your answers. Make sure to include the programming language name at the start of the Markdown code blocks. Avoid wrapping the whole response in triple backticks. The user works in a text editor called Neovim which has a concept for editors with open files, integrated unit test support, an output pane that shows the output of running the code as well as an integrated terminal. The active document is the source code the user is looking at right now. You can only give one reply for each conversation turn.
  ]],
  callbacks = {
    ---Set the parameters
    ---@param params table
    ---@param messages table
    ---@return table
    form_parameters = function(params, messages)
      -- As per: https://docs.anthropic.com/claude/docs/system-prompts
      -- Claude doesn't put the system prompt in the messages array, but in the parameters.system field
      local sys_prompts = get_system_prompts(messages)

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
      local sys_prompt = get_system_prompts(messages)
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
      desc = "The model that will complete your prompt. See https://docs.anthropic.com/claude/docs/models-overview for additional details and options.",
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
