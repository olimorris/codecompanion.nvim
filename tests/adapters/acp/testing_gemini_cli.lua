local acp_client = require("codecompanion.acp")
local adapters = require("codecompanion.adapters")
local log = require("codecompanion.utils.log")

print("🧪 Testing ACP Adapter System")

-- Setup CodeCompanion
require("codecompanion").setup({
  adapters = {
    acp = {
      gemini_cli = function()
        return require("codecompanion.adapters").extend("gemini_cli", {
          command = {
            "node",
            "/Users/Oli/Code/Neovim/gemini-cli/packages/cli",
            "--experimental-acp",
          },
          env = {
            GEMINI_API_KEY = "cmd:op read op://personal/Gemini_API/credential --no-newline",
            auth_method = "gemini-api-key",
          },
        })
      end,
    },
  },
  opts = {
    log_level = "DEBUG",
  },
})

local adapter = adapters.resolve("gemini_cli")

if not adapter then
  print("❌ Failed to create adapter")
  return
end

print("✅ Adapter created successfully")

-- Create ACP client
print("🔌 Creating ACP client...")
local client = acp_client.new({ adapter = adapter })

-- Start the client
print("🚀 Starting ACP client...")
if not client:start() then
  print("❌ Failed to start ACP client")
  return
end

print("✅ ACP client started successfully")
print("💬 Sending ACP initialize request...")

-- Step 1: initialize
client:request("initialize", {
  protocolVersion = 1, -- integer, not string!
  clientCapabilities = {
    fs = { readTextFile = true, writeTextFile = true },
  },
}, function(init_result, init_err)
  if init_err then
    print("❌ Initialize error:", vim.inspect(init_err))
    acp_client.stop(client)
    return
  end

  print("✅ ACP Initialize successful!")
  print("📝 Server capabilities:", vim.inspect(init_result))

  -- Step 2: authenticate if needed
  local function after_auth()
    -- Step 3: session/new
    print("💬 Sending session/new request...")
    client:request("session/new", {
      cwd = vim.loop.cwd(),
      mcpServers = {}, -- or fill in as needed
    }, function(session_result, session_err)
      if session_err or not session_result or not session_result.sessionId then
        print("❌ session/new error:", vim.inspect(session_err or session_result))
        acp_client.stop(client)
        return
      end

      local session_id = session_result.sessionId
      print("✅ session/new successful! sessionId:", session_id)

      -- Step 4: session/prompt
      print("💬 Sending session/prompt request...")
      client:request("session/prompt", {
        sessionId = session_id,
        prompt = {
          { type = "text", text = "Hello! What directory am I in? Just respond briefly." },
        },
      }, function(prompt_result, prompt_err)
        if prompt_err then
          print("❌ session/prompt error:", vim.inspect(prompt_err))
        else
          print("✅ session/prompt request sent! (Check for notifications for output)")
        end
        acp_client.stop(client)
        print("✅ Full ACP test complete!")
      end)
    end)
  end

  -- If authentication is required
  if init_result.authMethods and #init_result.authMethods > 0 then
    print("🔑 Authenticating...")
    -- Pick the first available method for demo; in real code, let user choose
    local methodId = init_result.authMethods[1].id
    client:request("authenticate", { methodId = "gemini-api-key" }, function(auth_result, auth_err)
      if auth_err then
        print("❌ Authenticate error:", vim.inspect(auth_err))
        acp_client.stop(client)
        return
      end
      print("✅ Authentication successful!")
      after_auth()
    end)
  else
    after_auth()
  end
end)

-- Listen for notifications (streamed output)
client.on_notification = function(msg)
  if msg.sessionUpdate == "agentMessageChunk" and msg.content and msg.content.type == "text" then
    print("🤖 Adapter says:", msg.content.text)
  elseif msg.sessionUpdate then
    print("🔔 ACP notification:", vim.inspect(msg))
  end
end

-- Safety cleanup after 30 seconds
vim.defer_fn(function()
  print("⏰ Test timeout - cleaning up")
  if client:is_running() then
    acp_client.stop(client)
  end
end, 30000)

print("🚀 Test started - check output above...")
