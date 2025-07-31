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
            -- api_key = "cmd:op read op://personal/Anthropic_API/credential --no-newline",
            manifest_path = "/Users/Oli/Code/Neovim/codex/codex-rs/Cargo.toml",
          },
        })
      end,
    },
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

-- Test the full workflow
print("⏳ Waiting for initialization...")
vim.defer_fn(function()
  if not client:is_running() then
    print("❌ Client is not running")
    return
  end

  print("💬 Sending initialize request...")

  -- Step 1: Initialize the connection
  client:request("initialize", client.adapter.parameters, function(result, err)
    if err then
      print("❌ Initialize error:", vim.inspect(err))
      acp_client.stop(client)
      return
    end

    print("✅ Initialize successful!")
    print("📝 Server info:", vim.inspect(result))

    -- Step 2: Create a new session
    print("🎯 Creating new session...")
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
        print("❌ Session creation error:", vim.inspect(session_err))
        acp_client.stop(client)
        return
      end

      print("✅ Session created!")
      print("📝 Session result:", vim.inspect(session_result))

      -- Step 3: Clean up
      print("🧹 Cleaning up...")
      acp_client.stop(client)
      print("✅ Test complete!")
    end)
  end)
end, 2000) -- Wait 2 seconds for process to start

-- Safety cleanup after 30 seconds
vim.defer_fn(function()
  print("⏰ Test timeout - cleaning up")
  if client:is_running() then
    acp_client.stop(client)
  end
end, 30000)

print("🚀 Test started - check output above...")
