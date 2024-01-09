local log = require("codecompanion.utils.log")

_G.codecompanion_jobs = {}

---@class CodeCompanion.Client
---@field secret_key string
---@field organization nil|string
local Client = {}

---@class CodeCompanion.ClientArgs
---@field secret_key string
---@field organization nil|string

---@param args CodeCompanion.ClientArgs
---@return CodeCompanion.Client
function Client.new(args)
  return setmetatable({
    secret_key = args.secret_key,
    organization = args.organization,
  }, { __index = Client })
end

---@param code integer
---@param stdout string
---@return nil|string
---@return nil|any
local function parse_response(code, stdout)
  if code ~= 0 then
    return string.format("Error: %s", stdout)
  end
  local ok, data = pcall(vim.json.decode, stdout, { luanil = { object = true } })
  if not ok then
    return string.format("Error malformed json: %s", data)
  end
  if data.error then
    return string.format("API Error: %s", data.error.message)
  end
  return nil, data
end

---@param url string
---@param payload table
---@param cb fun(err: nil|string, response: nil|table)
---@return integer The job ID
function Client:call(url, payload, cb)
  cb = log:wrap_cb(cb, "Response error: %s")
  local cmd = {
    "curl",
    url,
    "-H",
    "Content-Type: application/json",
    "-H",
    string.format("Authorization: Bearer %s", self.secret_key),
  }
  if self.organization then
    table.insert(cmd, "-H")
    table.insert(cmd, string.format("OpenAI-Organization: %s", self.organization))
  end
  log:trace("request command: %s", cmd)
  table.insert(cmd, "-d")
  table.insert(cmd, vim.json.encode(payload))
  log:trace("request payload: %s", payload)
  local stdout = ""

  vim.api.nvim_exec_autocmds("User", { pattern = "CodeCompanion", data = { status = "started" } })

  local jid = vim.fn.jobstart(cmd, {
    stdout_buffered = true,
    on_stdout = function(_, output)
      stdout = table.concat(output, "\n")
    end,
    on_exit = vim.schedule_wrap(function(_, code)
      log:trace("response: %s", stdout)
      local err, data = parse_response(code, stdout)
      if err then
        cb(err)
      else
        cb(nil, data)
      end

      vim.api.nvim_exec_autocmds(
        "User",
        { pattern = "CodeCompanion", data = { status = "finished" } }
      )
    end),
  })

  if jid == 0 then
    cb("Passed invalid arguments to curl")
  elseif jid == -1 then
    cb("'curl' is not executable")
  end

  return jid
end

local function get_stdout_line_iter()
  local pending = ""
  return function(data)
    local ret = {}
    for i, chunk in ipairs(data) do
      if i == 1 then
        if chunk == "" then
          table.insert(ret, pending)
          pending = ""
        else
          pending = pending .. chunk
        end
      else
        if data[1] ~= "" then
          table.insert(ret, pending)
        end
        pending = chunk
      end
    end
    return ret
  end
end

---@param url string
---@param payload table
---@param bufnr number
---@param cb fun(err: nil|string, chunk: nil|table, done: nil|boolean) Will be called multiple times until done is true
---@return integer The job ID
function Client:stream_call(url, payload, bufnr, cb)
  cb = log:wrap_cb(cb, "Response error: %s")
  payload.stream = true
  local cmd = {
    "curl",
    url,
    "-H",
    "Content-Type: application/json",
    "-H",
    string.format("Authorization: Bearer %s", self.secret_key),
  }
  if self.organization then
    table.insert(cmd, "-H")
    table.insert(cmd, string.format("OpenAI-Organization: %s", self.organization))
  end
  log:trace("stream request command: %s", cmd)
  table.insert(cmd, "-d")
  table.insert(cmd, vim.json.encode(payload))
  log:trace("stream request payload: %s", payload)
  local line_iter = get_stdout_line_iter()
  local stdout = ""
  local done = false
  local found_any_stream = false

  vim.api.nvim_exec_autocmds("User", { pattern = "CodeCompanion", data = { status = "started" } })

  local jid = vim.fn.jobstart(cmd, {
    on_stdout = function(_, output)
      if done then
        return
      end
      if not found_any_stream then
        stdout = stdout .. table.concat(output, "\n")
      end
      for _, line in ipairs(line_iter(output)) do
        log:trace("stream response line: %s", line)
        if vim.startswith(line, "data: ") then
          found_any_stream = true
          local chunk = line:sub(7)

          if chunk == "[DONE]" then
            return cb(nil, nil, true)
          end

          if _G.codecompanion_jobs[bufnr].status == "stopping" then
            done = true
            vim.fn.jobstop(_G.codecompanion_jobs[bufnr].jid)
            _G.codecompanion_jobs[bufnr] = nil
            return cb(nil, nil, true)
          end

          local ok, data = pcall(vim.json.decode, chunk, { luanil = { object = true } })
          if not ok then
            done = true
            return cb(string.format("Error malformed json: %s", data))
          end

          -- Check if the token limit has been reached
          log:debug("Finish Reason: %s", data.choices[1].finish_reason)
          if data.choices[1].finish_reason == "length" then
            log:debug("Token limit reached")
            done = true
            return cb("[CodeCompanion.nvim]\nThe token limit for the current chat has been reached")
          end

          cb(nil, data)
        end
      end
    end,
    on_exit = function(_, code)
      vim.api.nvim_exec_autocmds(
        "User",
        { pattern = "CodeCompanion", data = { status = "finished" } }
      )

      if not found_any_stream then
        local err, data = parse_response(code, stdout)
        if err then
          cb(err)
        else
          cb(nil, data, true)
        end
      end
    end,
  })
  if jid == 0 then
    cb("Passed invalid arguments to curl")
  elseif jid == -1 then
    cb("'curl' is not executable")
  else
    _G.codecompanion_jobs[bufnr] = {
      jid = jid,
      status = "running",
      strategy = "chat",
    }
  end
  return jid
end

---@class CodeCompanion.ChatMessage
---@field role "system"|"user"|"assistant"
---@field content string

---@class CodeCompanion.ChatSettings
---@field model string ID of the model to use. See the model endpoint compatibility table for details on which models work with the Chat API.
---@field temperature nil|number Defaults to 1. What sampling temperature to use, between 0 and 2. Higher values like 0.8 will make the output more random, while lower values like 0.2 will make it more focused and deterministic. We generally recommend altering this or top_p but not both.
---@field top_p nil|number Defaults to 1. An alternative to sampling with temperature, called nucleus sampling, where the model considers the results of the tokens with top_p probability mass. So 0.1 means only the tokens comprising the top 10% probability mass are considered. We generally recommend altering this or temperature but not both.
---@field n nil|integer Defaults to 1. How many chat completion choices to generate for each input message.
---@field stop nil|string|string[] Defaults to nil. Up to 4 sequences where the API will stop generating further tokens.
---@field max_tokens nil|integer Defaults to nil. The maximum number of tokens to generate in the chat completion. The total length of input tokens and generated tokens is limited by the model's context length.
---@field presence_penalty nil|number Defaults to 0. Number between -2.0 and 2.0. Positive values penalize new tokens based on whether they appear in the text so far, increasing the model's likelihood to talk about new topics.
---@field frequency_penalty nil|number Defaults to 0. Number between -2.0 and 2.0. Positive values penalize new tokens based on their existing frequency in the text so far, decreasing the model's likelihood to repeat the same line verbatim.
---@field logit_bias nil|table<integer, integer> Modify the likelihood of specified tokens appearing in the completion. Maps tokens (specified by their token ID) to an associated bias value from -100 to 100. Use https://platform.openai.com/tokenizer to find token IDs.
---@field user nil|string A unique identifier representing your end-user, which can help OpenAI to monitor and detect abuse. Learn more.

---@class CodeCompanion.ChatArgs : CodeCompanion.ChatSettings
---@field messages CodeCompanion.ChatMessage[] The messages to generate chat completions for, in the chat format.
---@field stream boolean? Whether to stream the chat output back to Neovim

---@param args CodeCompanion.ChatArgs
---@param cb fun(err: nil|string, response: nil|table)
---@return integer
function Client:chat(args, cb)
  args.stream = false
  return self:call("https://api.openai.com/v1/chat/completions", args, cb)
end

---@param args CodeCompanion.ChatArgs
---@param bufnr integer
---@param cb fun(err: nil|string, chunk: nil|table, done: nil|boolean) Will be called multiple times until done is true
---@return integer
function Client:stream_chat(args, bufnr, cb)
  return self:stream_call("https://api.openai.com/v1/chat/completions", args, bufnr, cb)
end

---@class CodeCompanion.AdvsorArgs
---@field model string ID of the model to use. See the model endpoint compatibility table for details on which models work with the Chat API.
---@field input nil|string The input text to use as a starting point for the edit.
---@field instruction string The instruction that tells the model how to edit the prompt.
---@field temperature nil|number Defaults to 1. What sampling temperature to use, between 0 and 2. Higher values like 0.8 will make the output more random, while lower values like 0.2 will make it more focused and deterministic. We generally recommend altering this or top_p but not both.
---@field top_p nil|number Defaults to 1. An alternative to sampling with temperature, called nucleus sampling, where the model considers the results of the tokens with top_p probability mass. So 0.1 means only the tokens comprising the top 10% probability mass are considered. We generally recommend altering this or temperature but not both.
---@field n nil|integer Defaults to 1. How many chat completion choices to generate for each input message.
function Client:advisor(args, cb)
  args.stream = false
  return self:call("https://api.openai.com/v1/chat/completions", args, cb)
end

---@class CodeCompanion.AuthorArgs
---@field model string ID of the model to use. See the model endpoint compatibility table for details on which models work with the Chat API.
---@field input nil|string The input text to use as a starting point for the edit.
---@field instruction string The instruction that tells the model how to edit the prompt.
---@field temperature nil|number Defaults to 1. What sampling temperature to use, between 0 and 2. Higher values like 0.8 will make the output more random, while lower values like 0.2 will make it more focused and deterministic. We generally recommend altering this or top_p but not both.
---@field top_p nil|number Defaults to 1. An alternative to sampling with temperature, called nucleus sampling, where the model considers the results of the tokens with top_p probability mass. So 0.1 means only the tokens comprising the top 10% probability mass are considered. We generally recommend altering this or temperature but not both.
---@field n nil|integer Defaults to 1. How many chat completion choices to generate for each input message.
function Client:author(args, cb)
  args.stream = false
  return self:call("https://api.openai.com/v1/chat/completions", args, cb)
end

return Client
