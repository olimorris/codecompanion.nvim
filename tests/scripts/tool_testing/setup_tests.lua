#!/usr/bin/env -S nvim -l

-- Simple test to verify CodeCompanion can be loaded
-- Run with: nvim -l scripts/tool_testing/test_setup.lua

-- Best result by test.sh wrapper for proper terminal rendering

-- Setup runtime path
local function setup_runtimepath()
  local script_path = debug.getinfo(1, "S").source:sub(2)
  local plugin_root = vim.fn.fnamemodify(script_path, ":h:h:h")

  print("Plugin root: " .. plugin_root)

  vim.opt.runtimepath:prepend(plugin_root)

  -- Load from lazy.nvim data directory
  local lazy_root = vim.fs.joinpath(vim.fn.stdpath("data"), "lazy")
  if vim.fn.isdirectory(lazy_root) == 1 then
    print("Found lazy.nvim directory: " .. lazy_root)

    local deps = {
      "codecompanion.nvim",
      "plenary.nvim",
      "nvim-treesitter",
    }

    for _, dep in ipairs(deps) do
      local dep_path = vim.fs.joinpath(lazy_root, dep)
      if vim.fn.isdirectory(dep_path) == 1 then
        vim.opt.runtimepath:prepend(dep_path)
        print("  Added: " .. dep)
      end
    end
  end

  -- Also try from .repro path (for minimal init)
  local repro_path = ".repro/plugins"
  if vim.fn.isdirectory(repro_path) == 1 then
    print("Found .repro directory: " .. repro_path)
    local deps = { "codecompanion.nvim", "plenary.nvim", "nvim-treesitter" }
    for _, dep in ipairs(deps) do
      local dep_path = vim.fs.joinpath(repro_path, dep)
      if vim.fn.isdirectory(dep_path) == 1 then
        vim.opt.runtimepath:prepend(dep_path)
        print("  Added: " .. dep)
      end
    end
  end

  print("\nLoaded runtime paths (codecompanion/plenary):")
  for _, path in ipairs(vim.opt.runtimepath:get()) do
    if path:match("codecompanion") or path:match("plenary") then
      print("  - " .. path)
    end
  end
end

setup_runtimepath()

print("\n" .. string.rep("=", 60))
print("Testing CodeCompanion Setup")
print(string.rep("=", 60) .. "\n")

-- Test 1: Load CodeCompanion module
print("Test 1: Loading CodeCompanion module...")
local ok, codecompanion = pcall(require, "codecompanion")
if ok then
  print("✓ SUCCESS: CodeCompanion loaded")
  print("  Version: " .. (codecompanion.version or "unknown"))
else
  print("✗ FAILED: Could not load CodeCompanion")
  print("  Error: " .. tostring(codecompanion))
  print("\nTroubleshooting:")
  print("  1. Make sure you're in the plugin root directory:")
  print("     cd /path/to/codecompanion.nvim")
  print("  2. Or run from anywhere with:")
  print("     cd /path/to/codecompanion.nvim && nvim -l scripts/tool_testing/test_setup.lua")
  vim.cmd("cquit 1")
end

-- Test 2: Check for required dependencies
print("\nTest 2: Checking dependencies...")
local deps = {
  "plenary",
  "plenary.curl",
  "plenary.path",
}

local all_deps_ok = true
for _, dep in ipairs(deps) do
  local dep_ok, _ = pcall(require, dep)
  if dep_ok then
    print("  ✓ " .. dep)
  else
    print("  ✗ " .. dep .. " (missing)")
    all_deps_ok = false
  end
end

if all_deps_ok then
  print("✓ SUCCESS: All dependencies found")
else
  print("✗ FAILED: Some dependencies missing")
  print("\nInstall missing dependencies:")
  print("  nvim-lua/plenary.nvim")
end

-- Test 3: Try to create an adapter
print("\nTest 3: Creating test adapter...")
local adapter_ok, adapter = pcall(function()
  return require("codecompanion.adapters").resolve("openai")
end)

if adapter_ok and adapter then
  print("✓ SUCCESS: Adapter created successfully")
  print("  Name: " .. (adapter.name or "unknown"))
  print("  URL: " .. (adapter.url or "unknown"))
else
  print("✗ FAILED: Could not create adapter")
  print("  Error: " .. tostring(adapter))
end

-- Test 4: Check config structure
print("\nTest 4: Loading test config...")
local config_path = vim.fs.joinpath(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h"), "config.lua")
local config_ok, config = pcall(dofile, config_path)

if config_ok and config then
  print("✓ SUCCESS: Config loaded")
  print("  Adapters defined: " .. #config.adapters)

  -- Check for API keys
  local has_keys = false
  for name, key in pairs(config.api_keys or {}) do
    if key and key ~= "" then
      has_keys = true
      print("  API key found for: " .. name)
    end
  end

  if not has_keys then
    print("\n  ⚠ No API keys configured")
    print("  Run: ./test.sh setup")
    print("  Then edit: config.local.lua")
  end
else
  print("✗ FAILED: Could not load config")
  print("  Error: " .. tostring(config))
end

-- Summary
print("\n" .. string.rep("=", 60))
print("Setup Verification Summary")
print(string.rep("=", 60))

if ok and all_deps_ok and adapter_ok and config_ok then
  print("\n✓ SUCCESS: All checks passed!")
  print("\nYou're ready to run tests:")
  print("  ./test.sh run --adapter=openai")
  os.exit(0)
else
  print("\n✗ FAILED: Some checks failed")
  print("\nFix the issues above before running tests")
  os.exit(1)
end
