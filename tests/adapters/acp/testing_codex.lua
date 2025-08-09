print("🧪 Testing ACP Adapter System")

local acp_client = require("codecompanion.acp")
local adapters = require("codecompanion.adapters")

-- Setup CodeCompanion
require("codecompanion").setup({
  adapters = {
    acp = {
      codex = function()
        return require("codecompanion.adapters").extend("codex", {
          command = {
            "cargo",
            "run",
            "--bin",
            "codex",
            "--manifest-path",
            "${manifest_path}",
            "mcp",
          },
          env = {
            OPENAI_API_KEY = "cmd:op read op://personal/OpenAI_API/credential --no-newline",
            manifest_path = "/Users/Oli/Code/Neovim/codex/codex-rs/Cargo.toml",
          },
        })
      end,
    },
  },
  opts = {
    log_level = "DEBUG",
  },
})

print("📡 Creating Codex adapter...")
local codex_adapter = adapters.resolve("codex")

if not codex_adapter then
  print("❌ Failed to create Codex adapter")
  return
end

print("✅ Codex adapter created successfully")

-- Create ACP client
print("🔌 Creating ACP client...")
local client = acp_client.new({ adapter = codex_adapter })

-- Start the client
print("🚀 Starting ACP client...")
if not client:start() then
  print("❌ Failed to start ACP client")
  return
end

print("✅ ACP client started successfully")
print(
  "📋 Adapter details:",
  vim.inspect({
    name = client.adapter.name,
    type = client.adapter.type,
    command = client.adapter.command,
  })
)

print("💬 Sending MCP initialize request...")

-- Step 1: Send MCP initialize (request)
client:request("initialize", {
  protocolVersion = "2024-11-05",
  capabilities = {},
  clientInfo = {
    name = "CodeCompanion",
    version = "1.0.0",
  },
}, function(result, err)
  if err then
    print("❌ Initialize error:", vim.inspect(err))
    acp_client.stop(client)
    return
  end

  print("✅ MCP Initialize successful!")
  print("📝 Server capabilities:", vim.inspect(result))

  -- Step 2: Send initialized notification (no callback expected)
  print("📤 Sending initialized notification...")

  -- Send as notification (we need to add this method)
  client:notify("initialized", {})

  -- Step 3: Now we can use ACP tools
  print("🎯 Testing ACP new_session...")
  client:request("tools/call", {
    name = "acp/new_session",
    arguments = {
      mcpServers = {},
      clientTools = {
        requestPermission = vim.NIL,
        writeTextFile = vim.NIL,
        readTextFile = vim.NIL,
      },
      cwd = ".",
    },
  }, function(session_result, session_err)
    if session_err then
      print("❌ Session error:", vim.inspect(session_err))
      acp_client.stop(client)
      return
    end

    print("✅ Session created:", vim.inspect(session_result))

    -- Extract session ID from the response
    local session_id = session_result.structuredContent.sessionId

    -- Step 4: Send a prompt to the session
    print("💬 Testing ACP prompt...")
    client:request("tools/call", {
      name = "acp/prompt",
      arguments = {
        sessionId = session_id,
        prompt = {
          {
            type = "text",
            text = "Hello! What directory am I in? Just respond briefly.",
          },
        },
      },
    }, function(prompt_result, prompt_err)
      if prompt_err then
        print("❌ Prompt error:", vim.inspect(prompt_err))
      else
        print("✅ Prompt successful:", vim.inspect(prompt_result))
      end

      acp_client.stop(client)
      print("✅ Full ACP test complete!")
    end)
  end)
end)

-- Safety cleanup after 30 seconds
vim.defer_fn(function()
  print("⏰ Test timeout - cleaning up")
  if client:is_running() then
    acp_client.stop(client)
  end
end, 30000)

print("🚀 Test started - check output above...")
