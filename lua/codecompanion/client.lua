local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")
local schema = require("codecompanion.schema")

_G.codecompanion_jobs = {}

---@param status string
local function fire_autocmd(status)
  vim.api.nvim_exec_autocmds("User", { pattern = "CodeCompanionRequest", data = { status = status } })
end

---@param bufnr? number
---@param handler? table
local function start_request(bufnr, handler)
  if bufnr and handler then
    _G.codecompanion_jobs[bufnr] = {
      status = "running",
      handler = handler,
    }
  end
  fire_autocmd("started")
end

---@param bufnr? number
---@param opts? table
local function close_request(bufnr, opts)
  if bufnr then
    if opts and opts.shutdown then
      _G.codecompanion_jobs[bufnr].handler:shutdown()
    end
    _G.codecompanion_jobs[bufnr] = nil
  end
  fire_autocmd("finished")
end

---@class CodeCompanion.Client
---@field secret_key string
---@field organization nil|string
---@field settings nil|table
local Client = {}

---@class CodeCompanion.ClientArgs
---@field secret_key string
---@field organization nil|string
---@field settings nil|table

---@param args CodeCompanion.ClientArgs
---@return CodeCompanion.Client
function Client.new(args)
  return setmetatable({
    secret_key = args.secret_key,
    organization = args.organization,
    settings = args.settings or schema.get_default(schema.static.client_settings, args.settings),
  }, { __index = Client })
end

---@param client CodeCompanion.Client
---@return table<string, string>
local function headers(client)
  local group = {
    content_type = "application/json",
    Authorization = "Bearer " .. client.secret_key,
    OpenAI_Organization = client.organization,
  }

  log:debug("Request Headers: %s", group)

  return group
end

---@param code integer
---@param stdout string
---@param settings table
---@return nil|string
---@return nil|any
local function parse_response(code, stdout, settings)
  if code ~= 0 then
    log:error("Error: %s", stdout)
    return string.format("Error: %s", stdout)
  end

  local ok, data = pcall(settings.decode, stdout, { luanil = { object = true } })
  if not ok then
    log:error("Error malformed json: %s", data)
    return string.format("Error malformed json: %s", data)
  end

  if data.error then
    log:error("API Error: %s", data.error.message)
    return string.format("API Error: %s", data.error.message)
  end

  return nil, data
end

---@param url string
---@param payload table
---@param cb fun(err: nil|string, response: nil|table)
function Client:call(url, payload, cb)
  cb = log:wrap_cb(cb, "Response error: %s")

  local handler = self.settings.request({
    url = url,
    raw = { "--no-buffer" },
    headers = headers(self),
    body = self.settings.encode(payload),
    callback = function(out)
      if out.exit then
        local err, data = parse_response(out.exit, out.body, self.settings)
        if err then
          self.settings.schedule(function()
            cb(err)
            log:error("Error: %s", err)
            close_request()
          end)
        else
          self.settings.schedule(function()
            cb(nil, data)
            log:debug("Response: %s", data)
            close_request()
          end)
        end
      end
    end,
    on_error = function(err, _, _)
      log:error("Error: %s", err)
      close_request()
    end,
  })

  log:debug("Request: %s", handler.args)
  start_request()
end

---@param url string
---@param payload table
---@param bufnr number
---@param cb fun(err: nil|string, chunk: nil|table, done: nil|boolean) Will be called multiple times until done is true
---@return nil
function Client:stream_call(url, payload, bufnr, cb)
  cb = log:wrap_cb(cb, "Response error: %s")

  local handler = self.settings.request({
    url = url,
    raw = { "--no-buffer" },
    headers = headers(self),
    body = self.settings.encode(payload),
    stream = function(_, chunk)
      chunk = chunk:sub(7)

      if chunk ~= "" then
        if chunk == "[DONE]" then
          self.settings.schedule(function()
            close_request(bufnr)
            return cb(nil, nil, true)
          end)
        else
          self.settings.schedule(function()
            if _G.codecompanion_jobs[bufnr] and _G.codecompanion_jobs[bufnr].status == "stopping" then
              close_request(bufnr, { shutdown = true })
              return cb(nil, nil, true)
            end

            local ok, data = pcall(self.settings.decode, chunk, { luanil = { object = true } })

            if not ok then
              log:error("Error malformed json: %s", data)
              close_request(bufnr)
              return cb(string.format("Error malformed json: %s", data))
            end

            if data.choices[1].finish_reason then
              log:debug("Finish Reason: %s", data.choices[1].finish_reason)
            end

            if data.choices[1].finish_reason == "length" then
              log:debug("Token limit reached")
              close_request(bufnr)
              return cb("[CodeCompanion.nvim]\nThe token limit for the current chat has been reached")
            end

            cb(nil, data)
          end)
        end
      end
    end,
    on_error = function(err, _, _)
      close_request(bufnr)
      log:error("Error: %s", err)
    end,
  })

  log:debug("Stream Request: %s", handler.args)
  start_request(bufnr, handler)
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
---@return nil
function Client:chat(args, cb)
  return self:call(config.options.base_url .. "/v1/chat/completions", args, cb)
end

---@param args CodeCompanion.ChatArgs
---@param bufnr integer
---@param cb fun(err: nil|string, chunk: nil|table, done: nil|boolean) Will be called multiple times until done is true
---@return nil
function Client:stream_chat(args, bufnr, cb)
  args.stream = true
  return self:stream_call(config.options.base_url .. "/v1/chat/completions", args, bufnr, cb)
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
  return self:call(config.options.base_url .. "/v1/chat/completions", args, cb)
end

---@class args CodeCompanion.InlineArgs
---@param bufnr integer
---@param cb fun(err: nil|string, chunk: nil|table, done: nil|boolean) Will be called multiple times until done is true
---@return nil
function Client:inline(args, bufnr, cb)
  args.stream = true
  return self:stream_call(config.options.base_url .. "/v1/chat/completions", args, bufnr, cb)
end

return Client
