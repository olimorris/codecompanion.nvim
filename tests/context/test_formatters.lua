local config = require("codecompanion.config")
local formatters = require("codecompanion.context.formatters")
local h = require("tests.helpers")
local notebook = require("codecompanion.context.formatters.builtin.jupyter_notebook")

local T = MiniTest.new_set()

local registered

local stub_module = "tests.formatters_stub"

T["Formatters"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      registered = vim.deepcopy(config.context.formatters)
    end,
    post_case = function()
      for extension in pairs(config.context.formatters) do
        config.context.formatters[extension] = nil
      end
      for extension, value in pairs(registered) do
        config.context.formatters[extension] = value
      end
      package.loaded[stub_module] = nil
    end,
  },
})

T["Formatters"]["returns the raw content when nothing is registered"] = function()
  local content, formatted = formatters.apply({ path = "/tmp/file.unregistered", raw = "hello" })
  h.eq(content, "hello")
  h.is_false(formatted)
end

T["Formatters"]["applies formatter registered as a function"] = function()
  config.context.formatters.txt = function(raw, path)
    return raw .. " from " .. path
  end

  local content, formatted = formatters.apply({ path = "/tmp/file.txt", raw = "hello" })
  h.eq(content, "hello from /tmp/file.txt")
  h.is_true(formatted)
end

T["Formatters"]["applies formatter registered as a module path"] = function()
  package.loaded[stub_module] = {
    format = function(raw, path)
      return raw .. " via a module at " .. path
    end,
  }
  config.context.formatters.txt = stub_module

  local content, formatted = formatters.apply({ path = "/tmp/file.txt", raw = "hello" })
  h.eq(content, "hello via a module at /tmp/file.txt")
  h.is_true(formatted)
end

T["Formatters"]["matches extensions regardless of case"] = function()
  config.context.formatters.txt = function()
    return "formatted"
  end

  local content, formatted = formatters.apply({ path = "/tmp/file.TXT", raw = "hello" })
  h.eq(content, "formatted")
  h.is_true(formatted)
end

T["Formatters"]["returns the raw content when a module cannot be resolved"] = function()
  config.context.formatters.txt = "not.a.real.module"

  local content, formatted = formatters.apply({ path = "/tmp/file.txt", raw = "hello" })
  h.eq(content, "hello")
  h.is_false(formatted)
end

T["Formatters"]["returns the raw content when formatter fails"] = function()
  config.context.formatters.txt = function()
    error("boom")
  end

  local content, formatted = formatters.apply({ path = "/tmp/file.txt", raw = "hello" })
  h.eq(content, "hello")
  h.is_false(formatted)
end

T["Formatters"]["returns the raw content when formatter returns no content"] = function()
  config.context.formatters.txt = function()
    return nil
  end

  local content, formatted = formatters.apply({ path = "/tmp/file.txt", raw = "hello" })
  h.eq(content, "hello")
  h.is_false(formatted)
end

T["Jupyter notebooks"] = MiniTest.new_set()

T["Jupyter notebooks"]["are formatted as cells, with image outputs stripped"] = function()
  local content = notebook.format(vim.json.encode({
    cells = {
      { cell_type = "markdown", source = { "# Notes" } },
      {
        cell_type = "code",
        source = { "print('hello')" },
        execution_count = 3,
        outputs = {
          { output_type = "stream", name = "stdout", text = { "hello" } },
          { output_type = "stream", name = "stderr", text = { "a warning" } },
          { output_type = "display_data", data = { ["image/png"] = "BASE64DATA", ["text/plain"] = "<Figure>" } },
        },
      },
      {
        cell_type = "code",
        source = { "1/0" },
        outputs = {
          {
            output_type = "error",
            ename = "ZeroDivisionError",
            evalue = "division by zero",
            traceback = { "\27[0;31mZeroDivisionError\27[0m: division by zero" },
          },
        },
      },
    },
    metadata = { kernelspec = { language = "python" } },
  }))

  h.expect_truthy(content:find("## Cell 1 (markdown)", 1, true))
  h.expect_truthy(content:find("# Notes", 1, true))
  h.expect_truthy(content:find("## Cell 2 (code) In [3]", 1, true))
  h.expect_truthy(content:find("````python", 1, true))
  h.expect_truthy(content:find("### Output", 1, true))
  h.expect_truthy(content:find("[stderr]\na warning", 1, true))
  h.expect_truthy(content:find("<Figure>", 1, true))
  h.expect_truthy(content:find("[image/png output removed]", 1, true))
  h.expect_truthy(content:find("## Cell 3 (code) In [ ]", 1, true))
  h.expect_truthy(content:find("ZeroDivisionError: division by zero", 1, true))
  h.eq(content:find("\27", 1, true), nil)
  h.eq(content:find("BASE64DATA", 1, true), nil)
end

T["Jupyter notebooks"]["return no content when they cannot be parsed"] = function()
  h.eq(notebook.format("not json"), nil)
end

return T
