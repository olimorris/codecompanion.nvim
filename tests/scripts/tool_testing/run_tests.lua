#!/usr/bin/env -S nvim -l

-- Automated tool testing runner for CodeCompanion
-- Usage: nvim -l tests/scripts/tool_testing/run_tests.lua [options]
-- Options:
--   --adapter=<name>  Run only specific adapter
--   --model=<name>    Run only specific model
--   --scenario=<name> Run only specific scenario
--   --delay=<ms>      Delay between scenarios in milliseconds (default: 0)
--   --verbose         Show detailed output

local SCRIPT_DIR = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h")

local function setup_runtimepath()
  local plugin_root = vim.fn.fnamemodify(SCRIPT_DIR, ":h:h:h")

  local rtp = vim.opt.runtimepath:get()
  local found = false
  for _, path in ipairs(rtp) do
    if path == plugin_root then
      found = true
      break
    end
  end

  if not found then
    vim.opt.runtimepath:prepend(plugin_root)
  end

  -- Prefer in-repo deps/ clones (same source as `make test`)
  local deps_root = vim.fs.joinpath(plugin_root, "deps")
  if vim.fn.isdirectory(deps_root) == 1 then
    local deps = { "plenary.nvim", "nvim-treesitter" }
    for _, dep in ipairs(deps) do
      local dep_path = vim.fs.joinpath(deps_root, dep)
      if vim.fn.isdirectory(dep_path) == 1 then
        vim.opt.runtimepath:prepend(dep_path)
      end
    end
    return
  end

  -- Fall back to lazy.nvim data directory
  local lazy_root = vim.fs.joinpath(vim.fn.stdpath("data"), "lazy")
  if vim.fn.isdirectory(lazy_root) == 1 then
    local deps = { "plenary.nvim", "nvim-treesitter" }
    for _, dep in ipairs(deps) do
      local dep_path = vim.fs.joinpath(lazy_root, dep)
      if vim.fn.isdirectory(dep_path) == 1 then
        vim.opt.runtimepath:prepend(dep_path)
      end
    end
    return
  end

  -- Fall back to .repro path
  local repro_path = ".repro/plugins"
  if vim.fn.isdirectory(repro_path) == 1 then
    local deps = { "plenary.nvim", "nvim-treesitter" }
    for _, dep in ipairs(deps) do
      local dep_path = vim.fs.joinpath(repro_path, dep)
      if vim.fn.isdirectory(dep_path) == 1 then
        vim.opt.runtimepath:prepend(dep_path)
      end
    end
  end
end

setup_runtimepath()

local function load_env_file()
  local env_path = vim.fs.joinpath(SCRIPT_DIR, ".env")
  if vim.fn.filereadable(env_path) == 0 then
    return
  end
  for line in io.lines(env_path) do
    if not line:match("^%s*#") and not line:match("^%s*$") then
      local key, value = line:match("^([^=]+)=(.*)")
      if key and value then
        key = vim.trim(key)
        value = vim.trim(value)
        value = value:match('^"(.*)"$') or value:match("^'(.*)'$") or value
        vim.fn.setenv(key, value)
      end
    end
  end
end

local function load_config()
  local config_path = vim.fs.joinpath(SCRIPT_DIR, "config.lua")
  local config = dofile(config_path)

  local local_config_path = vim.fs.joinpath(SCRIPT_DIR, "config.local.lua")
  if vim.fn.filereadable(local_config_path) == 1 then
    local local_config = dofile(local_config_path)
    config = vim.tbl_deep_extend("force", config, local_config)
  end

  return config
end

local function load_scenarios(tool)
  local pattern = tool and vim.fs.joinpath(SCRIPT_DIR, "scenarios", tool, "*.lua")
    or vim.fs.joinpath(SCRIPT_DIR, "scenarios", "*", "*.lua")
  local scenario_files = vim.fn.glob(pattern, false, true)
  local scenarios = {}
  for _, file in ipairs(scenario_files) do
    local ok, scenario = pcall(dofile, file)
    if ok and scenario then
      table.insert(scenarios, scenario)
    else
      print(string.format("[WARN] Failed to load scenario file: %s", file))
    end
  end
  return scenarios
end

local function register_custom_adapters(config)
  local log_messages = {}

  if not config.adapter_definitions or vim.tbl_isempty(config.adapter_definitions) then
    return log_messages
  end

  local cc_config = require("codecompanion.config")
  local adapters = require("codecompanion.adapters")

  for adapter_name, adapter_def in pairs(config.adapter_definitions) do
    if not adapter_def.extends then
      table.insert(log_messages, {
        level = "ERROR",
        msg = string.format("Custom adapter '%s' missing 'extends' field", adapter_name),
      })
      goto continue
    end

    local base_adapter = cc_config.adapters.http[adapter_def.extends]
    if not base_adapter then
      table.insert(log_messages, {
        level = "ERROR",
        msg = string.format("Custom adapter '%s' extends unknown adapter '%s'", adapter_name, adapter_def.extends),
      })
      goto continue
    end

    local custom_config = {
      name = adapter_name,
      formatted_name = adapter_name:gsub("^%l", string.upper):gsub("_(%l)", function(c)
        return " " .. c:upper()
      end),
    }

    if adapter_def.env then
      custom_config.env = adapter_def.env
    end
    if adapter_def.features then
      custom_config.features = adapter_def.features
    end
    if adapter_def.handlers then
      custom_config.handlers = adapter_def.handlers
    end
    if adapter_def.headers then
      custom_config.headers = adapter_def.headers
    end
    if adapter_def.opts then
      custom_config.opts = adapter_def.opts
    end
    if adapter_def.roles then
      custom_config.roles = adapter_def.roles
    end
    if adapter_def.schema then
      custom_config.schema = adapter_def.schema
    end
    if adapter_def.url then
      custom_config.url = adapter_def.url
    end

    local ok, custom_adapter = pcall(function()
      return adapters.extend(adapter_def.extends, custom_config)
    end)

    if ok and custom_adapter then
      cc_config.adapters.http[adapter_name] = custom_adapter
      table.insert(log_messages, {
        level = "INFO",
        msg = string.format("✓ Registered custom adapter: %s (extends %s)", adapter_name, adapter_def.extends),
      })
    else
      table.insert(log_messages, {
        level = "ERROR",
        msg = string.format("Failed to create custom adapter '%s': %s", adapter_name, tostring(custom_adapter)),
      })
    end

    ::continue::
  end

  return log_messages
end

local function validate_adapter_exists(adapter_name)
  local cc_config = require("codecompanion.config")

  if cc_config.adapters.http[adapter_name] or cc_config.adapters.acp[adapter_name] then
    return true, nil
  end

  local available = {}
  for name, _ in pairs(cc_config.adapters.http) do
    table.insert(available, name)
  end
  for name, _ in pairs(cc_config.adapters.acp) do
    table.insert(available, name)
  end
  table.sort(available)

  return false,
    string.format(
      "Adapter '%s' not found.\n\nAvailable built-in adapters:\n  %s\n\nTo use custom adapters, define them in config.adapter_definitions",
      adapter_name,
      table.concat(available, ", ")
    )
end

local function parse_args()
  local args = {
    adapter = nil,
    csv = false,
    delay = 0,
    model = nil,
    scenario = nil,
    tool = nil,
    verbose = false,
  }

  for _, arg in ipairs(vim.v.argv) do
    if arg:match("^%-%-adapter=") then
      args.adapter = arg:match("^%-%-adapter=(.+)$")
    elseif arg:match("^%-%-model=") then
      args.model = arg:match("^%-%-model=(.+)$")
    elseif arg:match("^%-%-scenario=") then
      args.scenario = arg:match("^%-%-scenario=(.+)$")
    elseif arg:match("^%-%-tool=") then
      args.tool = arg:match("^%-%-tool=(.+)$")
    elseif arg:match("^%-%-delay=") then
      args.delay = tonumber(arg:match("^%-%-delay=(.+)$")) or 0
    elseif arg == "--csv" then
      args.csv = true
    elseif arg == "--verbose" then
      args.verbose = true
    end
  end

  return args
end

local function setup_output_dir(config)
  local dir = config.output.results_dir
  vim.fn.mkdir(dir, "p")
  return dir
end

local function log(msg, level, verbose_only)
  level = level or "INFO"

  if verbose_only and not _G._test_verbose then
    return
  end

  if level == "PASS" then
    print(string.format("  ✓ PASS  %s", msg))
  elseif level == "FAIL" then
    print(string.format("  ✗ FAIL  %s", msg))
  elseif level == "ERROR" then
    print(string.format("  ✗ ERROR %s", msg))
  elseif level == "RUN" then
    print(string.format("  RUN %s", msg))
  else
    print(string.format("  %s", msg))
  end
end

local function csv_escape(value)
  value = tostring(value or "")
  if value:find('[,"\n]') then
    value = '"' .. value:gsub('"', '""') .. '"'
  end
  return value
end

local function write_csv_row(csv_file, result)
  local file_exists = vim.fn.filereadable(csv_file) == 1
  local f = io.open(csv_file, "a")
  if not f then
    log("Failed to open CSV file: " .. csv_file, "ERROR")
    return
  end
  if not file_exists then
    f:write("run_at,adapter,model,scenario,result,duration_s,tool_calls,error\n")
  end
  local row = {
    csv_escape(result.timestamp),
    csv_escape(result.adapter),
    csv_escape(result.model),
    csv_escape(result.scenario),
    csv_escape(result.success and "pass" or "fail"),
    csv_escape(string.format("%.2f", result.duration_ms / 1000)),
    csv_escape(tostring(#(result.tool_calls or {}))),
    csv_escape(result.error or ""),
  }
  f:write(table.concat(row, ",") .. "\n")
  f:close()
end

local function save_result(results_dir, adapter_name, scenario_name, result)
  local filename = vim.fs.joinpath(
    results_dir,
    string.format("%s_%s_%s.json", os.date("%Y%m%d_%H%M%S"), adapter_name, scenario_name:gsub("%s+", "_"))
  )

  vim.fn.writefile(vim.split(vim.json.encode(result), "\n"), filename)
  return filename
end

local function run_scenario_for_adapter(adapter_config, scenario, config, args)
  log(string.format("%s :: %s", adapter_config.model, scenario.name), "RUN")

  local result = {
    adapter = adapter_config.name,
    duration_ms = 0,
    error = nil,
    messages = {},
    model = adapter_config.model,
    response_content = "",
    scenario = scenario.name,
    success = false,
    timestamp = os.date("%Y-%m-%d %H:%M:%S"),
    tool_calls = {},
    validation = nil,
  }

  local start_time = vim.uv.hrtime()

  local context = {}
  local setup_ok, setup_result = pcall(scenario.setup)
  if not setup_ok then
    result.error = "Setup failed: " .. tostring(setup_result)
    result.duration_ms = (vim.uv.hrtime() - start_time) / 1000000
    return result
  end
  context = setup_result or {}

  local ok, codecompanion = pcall(require, "codecompanion")
  if not ok then
    result.error = "Failed to load CodeCompanion: " .. tostring(codecompanion)
    log(result.error, "ERROR")
    if scenario.cleanup then
      pcall(scenario.cleanup, context)
    end
    result.duration_ms = (vim.uv.hrtime() - start_time) / 1000000
    return result
  end

  local chat_ok, chat = pcall(function()
    return codecompanion.chat({
      auto_submit = false,
      hidden = true,
      params = { adapter = adapter_config.name, model = adapter_config.model },
      yolo_mode = true,
    })
  end)

  if not chat_ok or not chat then
    result.error = "Failed to create chat: " .. tostring(chat)
    if scenario.cleanup then
      pcall(scenario.cleanup, context)
    end
    result.duration_ms = (vim.uv.hrtime() - start_time) / 1000000
    return result
  end

  local cc_config = require("codecompanion.config")

  for _, tool_name in ipairs(scenario.tools) do
    local tool_config = cc_config.interactions.chat.tools and cc_config.interactions.chat.tools[tool_name]
    if not tool_config then
      result.error = "Tool not found in config: " .. tool_name
      pcall(function()
        chat:close()
      end)
      if scenario.cleanup then
        pcall(scenario.cleanup, context)
      end
      result.duration_ms = (vim.uv.hrtime() - start_time) / 1000000
      return result
    end

    local tool_added, add_err = pcall(function()
      chat.tool_registry:add(tool_name, tool_config)
    end)
    if not tool_added then
      result.error = "Failed to add tool: " .. tool_name .. " - " .. tostring(add_err)
      pcall(function()
        chat:close()
      end)
      if scenario.cleanup then
        pcall(scenario.cleanup, context)
      end
      result.duration_ms = (vim.uv.hrtime() - start_time) / 1000000
      return result
    end
  end

  local prompt = scenario.prompt(context)
  local completed = false
  local chat_done = false
  local tool_calls = {}
  local response_content = ""
  local tool_executed = false

  local function capture_tool_data()
    for _, msg in ipairs(chat.messages) do
      if msg.role == "llm" and msg.tools and msg.tools.calls then
        for _, tool_call in ipairs(msg.tools.calls) do
          local already_captured = false
          for _, captured in ipairs(tool_calls) do
            if captured.id == tool_call.id then
              already_captured = true
              break
            end
          end
          if not already_captured then
            table.insert(tool_calls, {
              arguments = tool_call["function"] and tool_call["function"].arguments or "{}",
              id = tool_call.id,
              name = tool_call["function"] and tool_call["function"].name or "unknown",
            })
          end
        end
      end
      if msg.role == "tool" then
        tool_executed = true
      end
      if msg.role == "llm" and msg.content then
        if not response_content:find(msg.content, 1, true) then
          response_content = response_content .. msg.content
        end
      end
    end
  end

  chat:add_callback("on_completed", function()
    chat_done = true
  end)
  chat:add_callback("on_cancelled", function()
    chat_done = true
    result.error = "Chat was cancelled"
  end)

  chat:add_message({ content = prompt, role = "user" })

  local submit_ok, submit_err = pcall(function()
    chat:submit({ auto_submit = true })

    local timeout = adapter_config.timeout or 30000
    local wait_time = 0
    local interval = 200

    while wait_time < timeout and not chat_done do
      vim.wait(interval)
      wait_time = wait_time + interval
      capture_tool_data()
    end

    if chat_done then
      capture_tool_data()
      completed = true
    else
      result.error = "Timeout waiting for response (waited " .. wait_time .. "ms)"
    end
  end)

  if not submit_ok then
    result.error = "Submit failed: " .. tostring(submit_err)
  end

  capture_tool_data()

  for _, msg in ipairs(chat.messages) do
    table.insert(result.messages, {
      _meta = msg._meta,
      content = type(msg.content) == "string" and msg.content or vim.inspect(msg.content),
      role = msg.role,
      tool_calls = msg.tools and msg.tools.calls or nil,
    })
  end

  if completed then
    -- Check tools_required before running validate
    if scenario.tools_required then
      for _, required in ipairs(scenario.tools_required) do
        local was_called = false
        for _, call in ipairs(tool_calls) do
          if call.name == required then
            was_called = true
            break
          end
        end
        if not was_called then
          result.success = false
          result.error = string.format("Required tool '%s' was not called", required)
          goto cleanup
        end
      end
    end

    local run_data = { response_content = response_content, tool_calls = tool_calls }
    local validate_ok, validate_success, validation_details = pcall(scenario.validate, context, run_data)
    if validate_ok then
      result.success = validate_success
      result.validation = validation_details
      if not validate_success and not result.error then
        result.error = "Validation failed"
      elseif validate_success then
        result.error = nil
      end
    else
      if not result.error then
        result.error = "Validation error: " .. tostring(validate_success)
      end
    end
  end

  if not result.success and #tool_calls > 0 then
    result.error = (result.error or "Unknown error")
      .. string.format(" (tool called: %s, executed: %s)", #tool_calls > 0, tool_executed)
  end

  ::cleanup::
  result.response_content = response_content
  result.tool_calls = tool_calls
  result.duration_ms = (vim.uv.hrtime() - start_time) / 1000000

  pcall(function()
    chat:close()
  end)
  if scenario.cleanup then
    pcall(scenario.cleanup, context)
  end

  return result
end

local function run_tests(config, args)
  log("Starting CodeCompanion Tool Tests", "INFO")
  log("================================", "INFO")

  local results_dir = setup_output_dir(config)
  log("Results directory: " .. results_dir, "INFO")

  local csv_file = config.output.csv_file
  if args.csv and not csv_file then
    csv_file = vim.fs.joinpath(results_dir, "results.csv")
  end
  if csv_file then
    log("CSV output: " .. csv_file, "INFO")
  end

  local registration_logs = register_custom_adapters(config)
  for _, entry in ipairs(registration_logs) do
    log(entry.msg, entry.level)
  end
  if #registration_logs > 0 then
    log("", "INFO")
  end

  local adapters_to_test = vim.tbl_filter(function(adapter)
    if not adapter.enabled then
      return false
    end
    if args.adapter and adapter.name ~= args.adapter then
      return false
    end
    return true
  end, config.adapters)

  local all_scenarios = load_scenarios(args.tool)
  local scenarios_to_test = vim.tbl_filter(function(scenario)
    if args.scenario and scenario.name ~= args.scenario then
      return false
    end
    return true
  end, all_scenarios)

  local test_runs = {}
  for _, adapter in ipairs(adapters_to_test) do
    local models = adapter.models or (adapter.model and { adapter.model } or { "default" })
    for _, model in ipairs(models) do
      if not args.model or model:find(args.model, 1, true) then
        local adapter_copy = vim.tbl_deep_extend("force", {}, adapter)
        adapter_copy.model = model
        adapter_copy.models = nil
        table.insert(test_runs, adapter_copy)
      end
    end
  end

  log(string.format("%d model(s) × %d scenario(s)", #test_runs, #scenarios_to_test), "INFO")

  local all_results = {}
  local summary = { errors = 0, failed = 0, passed = 0, total = 0 }

  for _, adapter in ipairs(test_runs) do
    local adapter_valid, adapter_error = validate_adapter_exists(adapter.name)
    if not adapter_valid then
      for _, scenario in ipairs(scenarios_to_test) do
        summary.total = summary.total + 1
        summary.errors = summary.errors + 1
        log(string.format("%s/%s - %s: %s", adapter.name, adapter.model, scenario.name, adapter_error), "ERROR")
        table.insert(all_results, {
          adapter = adapter.name,
          duration_ms = 0,
          error = adapter_error,
          messages = {},
          model = adapter.model,
          scenario = scenario.name,
          success = false,
          timestamp = os.date("%Y-%m-%d %H:%M:%S"),
          tool_calls = {},
          validation = nil,
        })
      end
      goto next_adapter
    end

    print("")

    for _, scenario in ipairs(scenarios_to_test) do
      summary.total = summary.total + 1

      local result = run_scenario_for_adapter(adapter, scenario, config, args)
      local call_count = #(result.tool_calls or {})
      local calls_str = call_count == 1 and "1 call" or (call_count .. " calls")

      if result.success then
        summary.passed = summary.passed + 1
        log(
          string.format(
            "%s/%s - %s (%.2fs, %s)",
            adapter.name,
            adapter.model,
            scenario.name,
            result.duration_ms / 1000,
            calls_str
          ),
          "PASS"
        )
      elseif result.error then
        summary.errors = summary.errors + 1
        log(
          string.format("%s/%s - %s: %s (%s)", adapter.name, adapter.model, scenario.name, result.error, calls_str),
          "ERROR"
        )
      else
        summary.failed = summary.failed + 1
        log(string.format("%s/%s - %s (%s)", adapter.name, adapter.model, scenario.name, calls_str), "FAIL")
      end

      if csv_file then
        write_csv_row(csv_file, result)
      end

      if config.output.save_logs then
        local adapter_model_name = adapter.name .. "_" .. adapter.model:gsub("[^%w]", "_")
        local result_file = save_result(results_dir, adapter_model_name, scenario.name, result)
        result.result_file = result_file
        log("  Result saved to: " .. result_file, "INFO", true)
      end

      if result.validation then
        log("  Validation: " .. vim.inspect(result.validation), "INFO", true)
      end
      if result.tool_calls and #result.tool_calls > 0 then
        log("  Tools called: " .. vim.inspect(result.tool_calls), "INFO", true)
      end

      table.insert(all_results, result)

      if args.delay > 0 and scenario ~= scenarios_to_test[#scenarios_to_test] then
        vim.wait(args.delay)
      end
    end

    ::next_adapter::
  end

  print("")
  log("================================", "INFO")
  log("Test Summary", "INFO")
  log("================================", "INFO")
  log(string.format("Total:  %d", summary.total), "INFO")
  log(string.format("Passed: %d", summary.passed), "INFO")
  log(string.format("Failed: %d", summary.failed), "INFO")
  log(string.format("Errors: %d", summary.errors), "INFO")
  log(string.format("Success Rate: %.1f%%", (summary.passed / summary.total) * 100), "INFO")

  local summary_file = vim.fs.joinpath(results_dir, "summary_" .. os.date("%Y%m%d_%H%M%S") .. ".json")
  vim.fn.writefile(vim.split(vim.json.encode({ results = all_results, summary = summary }), "\n"), summary_file)
  log("Summary saved to: " .. summary_file, "INFO", true)

  vim.cmd(string.format("cquit %d", summary.failed + summary.errors))
end

load_env_file()
local config = load_config()
local args = parse_args()

if args.verbose then
  config.output.verbose = true
  _G._test_verbose = true
else
  _G._test_verbose = false
end

local ok, err = pcall(run_tests, config, args)
if not ok then
  log("Fatal error: " .. tostring(err), "FATAL")
  vim.cmd("cquit 1")
end
