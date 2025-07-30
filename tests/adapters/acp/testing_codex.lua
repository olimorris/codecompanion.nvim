print("🧪 Testing ACP Adapter System")

local acp_client = require("codecompanion.acp")
local adapters = require("codecompanion.adapters")

-- Setup CodeCompanion
require("codecompanion").setup()

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
print(
  "📋 Adapter details:",
  vim.inspect({
    name = client.adapter.name,
    type = client.adapter.type,
    command = client.adapter.command,
  })
)

print("✅ ACP client started successfully")

-- Test the full workflow
local session_id = nil

-- Step 1: Wait for initialization
print("⏳ Waiting for initialization...")
vim.defer_fn(function()
  if not client:is_running() then
    print("❌ Client is not running")
    return
  end

  print("🎯 Creating new session...")

  -- Step 2: Create session
  client:new_session({ cwd = "." }, function(sid, err)
    if err then
      print("❌ Session creation error:", vim.inspect(err))
      client:stop()
      return
    end

    session_id = sid
    print("✅ Session created:", session_id)

    -- Step 3: Send a prompt
    print("💬 Sending prompt...")
    local messages = {
      { content = "Hello! Can you tell me what directory I'm in?", role = "user" },
    }

    client:prompt(session_id, messages, function(result, err)
      if err then
        print("❌ Prompt error:", vim.inspect(err))
      else
        print("✅ Prompt response:")
        print("📝 Status:", result.status)
        print("🤖 Content:", result.output.content)
      end

      -- Step 4: Clean up
      print("🧹 Cleaning up...")
      client:stop()
      print("✅ Test complete!")
    end)
  end)
end, 3000) -- Wait 3 seconds for initialization

-- Safety cleanup after 30 seconds
vim.defer_fn(function()
  print("⏰ Test timeout - cleaning up")
  if client:is_running() then
    client:stop()
  end
end, 30000)

print("🚀 Test started - check output above...")
