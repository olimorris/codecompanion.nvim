print("🧪 Testing CLI Adapter System")

local cli_adapters = require("codecompanion.cli_adapters")

-- Test configuration
local test_config = {
  config = {
    manifest_path = "/Users/Oli/Code/Neovim/Codex/codex-rs/Cargo.toml",
  },
  opts = {
    env = {
      OPENAI_API_KEY = "your-api-key-here", -- Replace with real key for actual testing
    },
  },
}

print("📡 Creating Codex adapter...")
local codex = cli_adapters.get_adapter("codex", test_config)

if not codex then
  print("❌ Failed to create Codex adapter")
  return
end

print("✅ Codex adapter created successfully")
print("📋 Active adapters:", vim.inspect(cli_adapters.list_active()))

-- Test the full workflow
local session_id = nil

-- Step 1: Wait for initialization
print("⏳ Waiting for initialization...")
vim.defer_fn(function()
  print("🎯 Creating new session...")

  -- Step 2: Create session
  codex:new_session({ cwd = "." }, function(sid, err)
    if err then
      print("❌ Session creation error:", vim.inspect(err))
      cli_adapters.stop_all()
      return
    end

    session_id = sid
    print("✅ Session created:", session_id)

    -- Step 3: Send a prompt
    print("💬 Sending prompt...")
    local messages = {
      { content = "Hello! Can you tell me what directory I'm in?", role = "user" },
    }

    codex:prompt(session_id, messages, function(result, err)
      if err then
        print("❌ Prompt error:", vim.inspect(err))
      else
        print("✅ Prompt response:")
        print("📝 Status:", result.status)
        print("🤖 Content:", result.output.content)
      end

      -- Step 4: Clean up
      print("🧹 Cleaning up...")
      cli_adapters.stop_all()
      print("✅ Test complete!")
    end)
  end)
end, 2000) -- Wait 2 seconds for initialization

-- Safety cleanup after 30 seconds
vim.defer_fn(function()
  print("⏰ Test timeout - cleaning up")
  cli_adapters.stop_all()
end, 30000)

print("🚀 Test started - check output above...")
