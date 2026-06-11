#!/usr/bin/env -S nvim -l

--[[
===============================================================================
Automated tool testing runner for CodeCompanion
Usage: nvim -l tests/scripts/tool_testing/run_tests.lua [options]

Options:
  --adapter=<name>  Run only specific adapter
  --model=<name>    Run only specific model
  --scenario=<name> Run only specific scenario
  --tool=<name>     Run only scenarios for a specific tool
  --delay=<ms>      Stagger delay between starting runs in milliseconds (default: 0)
  --verbose         Show detailed output
--]]

local SCRIPT_DIR = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h")

---Set the runtimepath to include this dir
---@return nil
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

---Allow users to specify a .env file and load into the env
---@return nil
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

---Merge the default config with the user's local config if it exists
---@return table The merged configuration
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

---Load the scenarios for each tool
---@param tool? string The tool to filter scenarios by
---@return table A list of scenario tables
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

---@param config table
---@return table A list of log messages with level and msg fields
local function register_custom_adapters(config)
  local log_messages = {}

  if not config.adapter_definitions or vim.tbl_isempty(config.adapter_definitions) then
    return log_messages
  end

  local cc_config = require("codecompanion.config")
  local adapters = require("codecompanion.adapters")

  for adapter, adapter_def in pairs(config.adapter_definitions) do
    if not adapter_def.extends then
      table.insert(log_messages, {
        level = "ERROR",
        msg = string.format("Custom adapter '%s' missing 'extends' field", adapter),
      })
      goto continue
    end

    local base_adapter = cc_config.adapters.http[adapter_def.extends]
    if not base_adapter then
      table.insert(log_messages, {
        level = "ERROR",
        msg = string.format("Custom adapter '%s' extends unknown adapter '%s'", adapter, adapter_def.extends),
      })
      goto continue
    end

    local custom_config = {
      name = adapter,
      formatted_name = adapter:gsub("^%l", string.upper):gsub("_(%l)", function(c)
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
      cc_config.adapters.http[adapter] = custom_adapter
      table.insert(log_messages, {
        level = "INFO",
        msg = string.format("✓ Registered custom adapter: %s (extends %s)", adapter, adapter_def.extends),
      })
    else
      table.insert(log_messages, {
        level = "ERROR",
        msg = string.format("Failed to create custom adapter '%s': %s", adapter, tostring(custom_adapter)),
      })
    end

    ::continue::
  end

  return log_messages
end

---Ensure that the specified adapter exists
---@param adapter string
---@return boolean, string|nil
local function validate_adapter_exists(adapter)
  local cc_config = require("codecompanion.config")

  if cc_config.adapters.http[adapter] or cc_config.adapters.acp[adapter] then
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
      adapter,
      table.concat(available, ", ")
    )
end

---Parse any arguments to the runner
---@return table A table of parsed arguments
local function parse_args()
  local args = {
    adapter = nil,
    csv = false,
    delay = 0,
    log = false,
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
    elseif arg == "--log" then
      args.log = true
    elseif arg == "--verbose" then
      args.verbose = true
    end
  end

  return args
end

---@param config table
---@return string The path to the results directory
local function setup_output_dir(config)
  local dir = config.output.results_dir
  vim.fn.mkdir(dir, "p")
  return dir
end

-- Terminal UI state — populated by ui_init(), read everywhere else
local UI = {
  cols = 150,
  cuu1 = "", -- cursor-up-1 escape sequence
  el = "", -- erase-to-end-of-line escape sequence
  is_tty = false,
}

local ICONS = {
  error = " ",
  fail = " ",
  pass = " ",
  run = " ",
}

---@param opts {msg: string, level?: string, verbose_only?: boolean}
local function log(opts)
  local msg = opts.msg
  local level = opts.level or "INFO"
  local verbose_only = opts.verbose_only

  if verbose_only and not _G._test_verbose then
    return
  end

  local green = UI.is_tty and "\027[0;32m" or ""
  local red = UI.is_tty and "\027[0;31m" or ""
  local yellow = UI.is_tty and "\027[1;33m" or ""
  local cyan = UI.is_tty and "\027[0;36m" or ""
  local reset = UI.is_tty and "\027[0m" or ""

  if level == "PASS" then
    print(string.format("  %s%s PASS  %s%s", green, ICONS.pass, msg, reset))
  elseif level == "FAIL" then
    print(string.format("  %s%s FAIL  %s%s", red, ICONS.fail, msg, reset))
  elseif level == "ERROR" then
    print(string.format("  %s%s ERROR %s%s", red, ICONS.error, msg, reset))
  elseif level == "RUN" then
    local model, scenario = msg:match("^(.+) :: (.+)$")
    if model and scenario then
      print(string.format("  RUN %s%s%s :: %s%s%s", yellow, model, reset, cyan, scenario, reset))
    else
      print(string.format("  RUN %s", msg))
    end
  else
    print(string.format("  %s", msg))
  end
end

---Escape a value for safe inclusion in a CSV file
---@param value any The value to escape
---@return string The escaped value
local function csv_escape(value)
  value = tostring(value or "")
  if value:find('[,"\n]') then
    value = '"' .. value:gsub('"', '""') .. '"'
  end
  return value
end

---@param opts {csv_file: string, result: table}
local function write_csv_row(opts)
  local csv_file = opts.csv_file
  local result = opts.result

  local file_exists = vim.fn.filereadable(csv_file) == 1
  local f = io.open(csv_file, "a")
  if not f then
    log({ msg = "Failed to open CSV file: " .. csv_file, level = "ERROR" })
    return
  end
  if not file_exists then
    f:write("run_at,adapter,model,scenario,result,duration_s,tool_calls,tokens,error\n")
  end
  local row = {
    csv_escape(result.timestamp),
    csv_escape(result.adapter),
    csv_escape(result.model),
    csv_escape(result.scenario),
    csv_escape(result.success and "pass" or "fail"),
    csv_escape(string.format("%.2f", result.duration_ms / 1000)),
    csv_escape(tostring(#(result.tool_calls or {}))),
    csv_escape(tostring(result.tokens or 0)),
    csv_escape(result.error or ""),
  }
  f:write(table.concat(row, ",") .. "\n")
  f:close()
end

---@param opts {results_dir: string, adapter_name: string, scenario_name: string, result: table}
---@return string The path to the saved result file
local function save_result(opts)
  local results_dir = opts.results_dir
  local adapter_name = opts.adapter_name
  local scenario_name = opts.scenario_name
  local result = opts.result

  local filename = vim.fs.joinpath(
    results_dir,
    string.format("%s_%s_%s.json", os.date("%Y%m%d_%H%M%S"), adapter_name, scenario_name:gsub("%s+", "_"))
  )

  vim.fn.writefile(vim.split(vim.json.encode(result), "\n"), filename)
  return filename
end

---Detect whether stdout is a terminal and capture tput sequences
local function ui_init()
  local tty_check = os.execute("test -t 1")
  if tty_check ~= true and tty_check ~= 0 then
    return
  end

  local function shell(cmd)
    local handle = io.popen(cmd .. " 2>/dev/null")
    if not handle then
      return ""
    end
    local result = handle:read("*a") or ""
    handle:close()
    return result
  end

  -- Query terminal width via stty (reads winsize via ioctl on /dev/tty).
  local cols
  local _, c = shell("stty size < /dev/tty"):match("(%d+)%s+(%d+)")
  if c then
    cols = tonumber(c)
  end
  if not cols or cols <= 0 then
    cols = tonumber(os.getenv("COLUMNS"))
  end
  if not cols or cols <= 0 then
    cols = tonumber(shell("tput cols"))
  end
  if not cols or cols <= 0 then
    return
  end

  UI.cols = cols
  UI.cuu1 = shell("tput cuu1")
  UI.el = shell("tput el")
  UI.is_tty = true
end

---Truncate a string to fit within the terminal width, appending … if needed.
---@param str string
---@return string
local function ui_truncate(str)
  if vim.fn.strdisplaywidth(str) <= UI.cols then
    return str
  end
  local chars = vim.fn.strchars(str)
  while chars > 0 and vim.fn.strdisplaywidth(vim.fn.strcharpart(str, 0, chars) .. "…") > UI.cols do
    chars = chars - 1
  end
  return vim.fn.strcharpart(str, 0, chars) .. "…"
end

---Format a single run as one terminal line, using its current state
---@param run table
---@return string
local function ui_format_run_line(run)
  local adapter = run.adapter_config
  local label = string.format("%s/%s - %s", adapter.name, adapter.model, run.scenario.name)

  local plain, color
  if not run.finalized then
    plain = string.format("  %s  %s", ICONS.run, label)
    color = "\027[2m"
  else
    local result = run.result
    local call_count = #(result.tool_calls or {})
    local calls_str = call_count == 1 and "1 call" or (call_count .. " calls")
    local tokens_str = string.format("%d tokens", result.tokens or 0)

    if result.success then
      plain = string.format(
        "  %s PASS  %s (%.2fs, %s, %s)",
        ICONS.pass,
        label,
        result.duration_ms / 1000,
        calls_str,
        tokens_str
      )
      color = "\027[0;32m"
    elseif result.error then
      plain = string.format("  %s ERROR %s: %s (%s, %s)", ICONS.error, label, result.error, calls_str, tokens_str)
      color = "\027[0;31m"
    else
      plain = string.format("  %s FAIL  %s (%s, %s)", ICONS.fail, label, calls_str, tokens_str)
      color = "\027[0;31m"
    end
  end

  return color .. ui_truncate(plain) .. "\027[0m"
end

---Print the run block for the first time (all runs shown as pending).
---@param runs table
local function ui_print_block(runs)
  for _, run in ipairs(runs) do
    io.write(ui_format_run_line(run) .. "\n")
  end
  io.flush()
end

---Move the cursor back to the top of the run block and redraw each line
---@param runs table
local function ui_redraw_block(runs)
  io.write(string.rep(UI.cuu1, #runs))
  for _, run in ipairs(runs) do
    io.write(UI.el .. ui_format_run_line(run) .. "\n")
  end
  io.flush()
end

---Start a scenario run asynchronously
---@param opts {adapter_config: table, scenario: table}
---@return table The run object
local function start_scenario_run(opts)
  local adapter_config = opts.adapter_config
  local scenario = opts.scenario

  local run = {
    adapter_config = adapter_config,
    capture = nil,
    chat = nil,
    completed = false,
    context = {},
    done = false,
    finalized = false,
    response_content = "",
    result = {
      adapter = adapter_config.name,
      duration_ms = 0,
      error = nil,
      messages = {},
      model = adapter_config.model,
      response_content = "",
      scenario = scenario.name,
      success = false,
      timestamp = os.date("%Y-%m-%d %H:%M:%S"),
      tokens = 0,
      tool_calls = {},
      validation = nil,
    },
    scenario = scenario,
    start_time = vim.uv.hrtime(),
    timeout = adapter_config.timeout or 30000,
    tool_calls = {},
    tool_executed = false,
  }

  local function fail(msg)
    run.result.error = msg
    run.result.duration_ms = (vim.uv.hrtime() - run.start_time) / 1000000
    run.done = true
    return run
  end

  local setup_ok, setup_result = pcall(scenario.setup)
  if not setup_ok then
    return fail("Setup failed: " .. tostring(setup_result))
  end
  run.context = setup_result or {}

  local ok, codecompanion = pcall(require, "codecompanion")
  if not ok then
    return fail("Failed to load CodeCompanion: " .. tostring(codecompanion))
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
    return fail("Failed to create chat: " .. tostring(chat))
  end

  run.chat = chat

  local cc_config = require("codecompanion.config")

  for _, tool_name in ipairs(scenario.tools) do
    local tool_config = cc_config.interactions.chat.tools and cc_config.interactions.chat.tools[tool_name]
    if not tool_config then
      pcall(function()
        chat:close()
      end)
      return fail("Tool not found in config: " .. tool_name)
    end

    local tool_added, add_err = pcall(function()
      chat.tool_registry:add(tool_name, tool_config)
    end)
    if not tool_added then
      pcall(function()
        chat:close()
      end)
      return fail("Failed to add tool: " .. tool_name .. " - " .. tostring(add_err))
    end
  end

  run.capture = function()
    for _, msg in ipairs(chat.messages) do
      if msg.role == "llm" and msg.tools and msg.tools.calls then
        for _, tool_call in ipairs(msg.tools.calls) do
          local already_captured = false
          for _, captured in ipairs(run.tool_calls) do
            if captured.id == tool_call.id then
              already_captured = true
              break
            end
          end
          if not already_captured then
            table.insert(run.tool_calls, {
              arguments = tool_call["function"] and tool_call["function"].arguments or "{}",
              id = tool_call.id,
              name = tool_call["function"] and tool_call["function"].name or "unknown",
            })
          end
        end
      end
      if msg.role == "tool" then
        run.tool_executed = true
      end
      if msg.role == "llm" and msg.content then
        if not run.response_content:find(msg.content, 1, true) then
          run.response_content = run.response_content .. msg.content
        end
      end
    end
  end

  chat:add_callback("on_completed", function()
    run.completed = true
    run.done = true
  end)
  chat:add_callback("on_cancelled", function()
    run.result.error = "Chat was cancelled"
    run.done = true
  end)

  local prompt = scenario.prompt(run.context)
  chat:add_message({ content = prompt, role = "user" })

  local submit_ok, submit_err = pcall(function()
    chat:submit({ auto_submit = true })
  end)

  if not submit_ok then
    return fail("Submit failed: " .. tostring(submit_err))
  end

  return run
end

---Validate, build messages, and set result.success on a completed run.
---@param run table
local function finalize_run(run)
  local scenario = run.scenario
  local result = run.result

  run.capture()

  if run.chat then
    for _, msg in ipairs(run.chat.messages) do
      table.insert(result.messages, {
        _meta = msg._meta,
        content = type(msg.content) == "string" and msg.content or vim.inspect(msg.content),
        role = msg.role,
        tool_calls = msg.tools and msg.tools.calls or nil,
      })
    end
    result.tokens = (run.chat.ui and run.chat.ui.tokens) or 0
    pcall(function()
      run.chat:close()
    end)
  end

  result.duration_ms = (vim.uv.hrtime() - run.start_time) / 1000000

  if run.completed then
    local should_validate = true

    if scenario.tools_required then
      for _, required in ipairs(scenario.tools_required) do
        local was_called = false
        for _, call in ipairs(run.tool_calls) do
          if call.name == required then
            was_called = true
            break
          end
        end
        if not was_called then
          result.error = string.format("Required tool '%s' was not called", required)
          should_validate = false
          break
        end
      end
    end

    if should_validate then
      local run_data = { response_content = run.response_content, tool_calls = run.tool_calls }
      local validate_ok, validate_success, validation_details = pcall(scenario.validate, run.context, run_data)
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
  end

  if not result.success and #run.tool_calls > 0 then
    result.error = (result.error or "Unknown error")
      .. string.format(" (tool called: %s, executed: %s)", #run.tool_calls > 0, run.tool_executed)
  end

  result.response_content = run.response_content
  result.tool_calls = run.tool_calls

  if scenario.cleanup then
    pcall(scenario.cleanup, run.context)
  end
end

---@param opts {config: table, args: table}
local function run_tests(opts)
  local config = opts.config
  local args = opts.args

  log({ msg = "Starting CodeCompanion Tool Tests" })
  log({ msg = "================================" })

  local results_dir = setup_output_dir(config)
  log({ msg = "Results directory: " .. results_dir })

  local csv_file = config.output.csv_file
  if args.csv and not csv_file then
    csv_file = vim.fs.joinpath(results_dir, "results.csv")
  end
  if csv_file then
    log({ msg = "CSV output: " .. csv_file })
  end

  local registration_logs = register_custom_adapters(config)
  for _, entry in ipairs(registration_logs) do
    log({ msg = entry.msg, level = entry.level })
  end
  if #registration_logs > 0 then
    log({ msg = "" })
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

  log({ msg = string.format("%d model(s) × %d scenario(s)", #test_runs, #scenarios_to_test) })

  local all_results = {}
  local summary = { errors = 0, failed = 0, passed = 0, total = 0 }

  -- Start all runs in parallel; invalid adapters are resolved immediately
  local active_runs = {}

  for _, adapter in ipairs(test_runs) do
    local adapter_valid, adapter_error = validate_adapter_exists(adapter.name)
    if not adapter_valid then
      for _, scenario in ipairs(scenarios_to_test) do
        summary.total = summary.total + 1
        summary.errors = summary.errors + 1
        log({
          msg = string.format("%s/%s - %s: %s", adapter.name, adapter.model, scenario.name, adapter_error),
          level = "ERROR",
        })
        table.insert(all_results, {
          adapter = adapter.name,
          duration_ms = 0,
          error = adapter_error,
          messages = {},
          model = adapter.model,
          scenario = scenario.name,
          success = false,
          timestamp = os.date("%Y-%m-%d %H:%M:%S"),
          tokens = 0,
          tool_calls = {},
          validation = nil,
        })
      end
    else
      local use_block = UI.is_tty and not args.verbose
      if not use_block then
        print("")
      end
      for _, scenario in ipairs(scenarios_to_test) do
        if not use_block then
          log({ msg = string.format("%s :: %s", adapter.model, scenario.name), level = "RUN" })
        end
        local run = start_scenario_run({ adapter_config = adapter, scenario = scenario })
        table.insert(active_runs, run)
        if args.delay > 0 then
          vim.wait(args.delay)
        end
      end
    end
  end

  -- Single wait loop — all HTTP requests are in-flight concurrently
  if #active_runs > 0 then
    print("")
    if UI.is_tty and not args.verbose then
      ui_print_block(active_runs)
    end
  end

  while true do
    vim.wait(200)

    local still_pending = 0

    for _, run in ipairs(active_runs) do
      if not run.done then
        run.capture()
        local elapsed_ms = (vim.uv.hrtime() - run.start_time) / 1000000
        if elapsed_ms > run.timeout then
          run.result.error = string.format("Timeout waiting for response (waited %dms)", math.floor(elapsed_ms))
          run.done = true
        else
          still_pending = still_pending + 1
        end
      end

      if run.done and not run.finalized then
        run.finalized = true
        finalize_run(run)

        local result = run.result
        local scenario = run.scenario
        local adapter = run.adapter_config
        local call_count = #(result.tool_calls or {})
        local calls_str = call_count == 1 and "1 call" or (call_count .. " calls")
        local tokens_str = string.format("%d tokens", result.tokens or 0)

        summary.total = summary.total + 1
        if result.success then
          summary.passed = summary.passed + 1
        elseif result.error then
          summary.errors = summary.errors + 1
        else
          summary.failed = summary.failed + 1
        end

        if UI.is_tty and not args.verbose then
          ui_redraw_block(active_runs)
        else
          if result.success then
            log({
              msg = string.format(
                "%s/%s - %s (%.2fs, %s, %s)",
                adapter.name,
                adapter.model,
                scenario.name,
                result.duration_ms / 1000,
                calls_str,
                tokens_str
              ),
              level = "PASS",
            })
          elseif result.error then
            log({
              msg = string.format(
                "%s/%s - %s: %s (%s, %s)",
                adapter.name,
                adapter.model,
                scenario.name,
                result.error,
                calls_str,
                tokens_str
              ),
              level = "ERROR",
            })
          else
            log({
              msg = string.format(
                "%s/%s - %s (%s, %s)",
                adapter.name,
                adapter.model,
                scenario.name,
                calls_str,
                tokens_str
              ),
              level = "FAIL",
            })
          end
        end

        if csv_file then
          write_csv_row({ csv_file = csv_file, result = result })
        end

        if args.log and config.output.save_logs then
          local adapter_model_name = adapter.name .. "_" .. adapter.model:gsub("[^%w]", "_")
          local result_file = save_result({
            adapter_name = adapter_model_name,
            result = result,
            results_dir = results_dir,
            scenario_name = scenario.name,
          })
          result.result_file = result_file
          log({ msg = "  Result saved to: " .. result_file, verbose_only = true })
        end

        if result.validation then
          log({ msg = "  Validation: " .. vim.inspect(result.validation), verbose_only = true })
        end
        if result.tool_calls and #result.tool_calls > 0 then
          log({ msg = "  Tools called: " .. vim.inspect(result.tool_calls), verbose_only = true })
        end

        table.insert(all_results, result)
      end
    end

    if still_pending == 0 then
      break
    end
  end

  -- Explicit reset before summary to prevent color bleed from the last result line
  if UI.is_tty then
    io.write("\027[0m")
  end

  local function tty_color(str, ansi)
    return UI.is_tty and (ansi .. str .. "\027[0m") or str
  end

  io.write("\n")
  io.write("  ================================\n")
  io.write("  Test Summary\n")
  io.write("  ================================\n")
  io.write(string.format("  Total:  %d\n", summary.total))
  io.write(string.format("  Passed: %s\n", tty_color(tostring(summary.passed), "\027[0;32m")))
  io.write(
    string.format(
      "  Failed: %s\n",
      summary.failed > 0 and tty_color(tostring(summary.failed), "\027[0;31m") or tostring(summary.failed)
    )
  )
  io.write(
    string.format(
      "  Errors: %s\n",
      summary.errors > 0 and tty_color(tostring(summary.errors), "\027[0;31m") or tostring(summary.errors)
    )
  )

  local success_rate = summary.total > 0 and (summary.passed / summary.total) * 100 or 0
  local rate_color = success_rate >= 50 and "\027[0;32m" or "\027[0;31m"
  io.write(string.format("  Success Rate: %s\n", tty_color(string.format("%.1f%%", success_rate), rate_color)))
  io.flush()

  if args.log then
    local summary_file = vim.fs.joinpath(results_dir, "summary_" .. os.date("%Y%m%d_%H%M%S") .. ".json")
    vim.fn.writefile(vim.split(vim.json.encode({ results = all_results, summary = summary }), "\n"), summary_file)
    log({ msg = "Summary saved to: " .. summary_file, verbose_only = true })
  end

  vim.cmd(string.format("cquit %d", summary.failed + summary.errors))
end

load_env_file()
ui_init()
local config = load_config()
local args = parse_args()

if args.verbose then
  config.output.verbose = true
  _G._test_verbose = true
else
  _G._test_verbose = false
end

local ok, err = pcall(run_tests, { config = config, args = args })
if not ok then
  log({ msg = "Fatal error: " .. tostring(err), level = "FATAL" })
  vim.cmd("cquit 1")
end
