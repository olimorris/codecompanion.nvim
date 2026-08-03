local config = require("codecompanion.config")
local h = require("tests.helpers")
local middleware = require("codecompanion.interactions.shared.middleware")
local notebook = require("codecompanion.interactions.shared.middleware.jupyter_notebook")

local T = MiniTest.new_set()

local registered

T["Middleware"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      registered = vim.deepcopy(config.middleware)
    end,
    post_case = function()
      for extension in pairs(config.middleware) do
        config.middleware[extension] = nil
      end
      for extension, value in pairs(registered) do
        config.middleware[extension] = value
      end
    end,
  },
})

T["Middleware"]["returns the raw content when nothing is registered"] = function()
  local content, formatted = middleware.apply({ path = "/tmp/file.unregistered", raw = "hello" })
  h.eq(content, "hello")
  h.is_false(formatted)
end

T["Middleware"]["applies middleware registered as a function"] = function()
  config.middleware.txt = function(raw, path)
    return raw .. " from " .. path
  end

  local content, formatted = middleware.apply({ path = "/tmp/file.txt", raw = "hello" })
  h.eq(content, "hello from /tmp/file.txt")
  h.is_true(formatted)
end

T["Middleware"]["applies middleware registered as a module path"] = function()
  config.middleware.txt = "codecompanion.interactions.shared.middleware.jupyter_notebook"

  local _, formatted = middleware.apply({
    path = "/tmp/file.txt",
    raw = vim.json.encode({ cells = {} }),
  })
  h.is_true(formatted)
end

T["Middleware"]["matches extensions regardless of case"] = function()
  config.middleware.txt = function()
    return "formatted"
  end

  local content, formatted = middleware.apply({ path = "/tmp/file.TXT", raw = "hello" })
  h.eq(content, "formatted")
  h.is_true(formatted)
end

T["Middleware"]["returns the raw content when a module cannot be resolved"] = function()
  config.middleware.txt = "not.a.real.module"

  local content, formatted = middleware.apply({ path = "/tmp/file.txt", raw = "hello" })
  h.eq(content, "hello")
  h.is_false(formatted)
end

T["Middleware"]["returns the raw content when middleware fails"] = function()
  config.middleware.txt = function()
    error("boom")
  end

  local content, formatted = middleware.apply({ path = "/tmp/file.txt", raw = "hello" })
  h.eq(content, "hello")
  h.is_false(formatted)
end

T["Middleware"]["returns the raw content when middleware returns no content"] = function()
  config.middleware.txt = function()
    return nil
  end

  local content, formatted = middleware.apply({ path = "/tmp/file.txt", raw = "hello" })
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
        outputs = {
          { output_type = "stream", text = { "hello" } },
          { output_type = "display_data", data = { ["image/png"] = "BASE64DATA", ["text/plain"] = "<Figure>" } },
        },
      },
    },
    metadata = { kernelspec = { language = "python" } },
  }))

  h.expect_truthy(content:find("## markdown", 1, true))
  h.expect_truthy(content:find("# Notes", 1, true))
  h.expect_truthy(content:find("````python", 1, true))
  h.expect_truthy(content:find("### Output", 1, true))
  h.expect_truthy(content:find("<Figure>", 1, true))
  h.eq(content:find("BASE64DATA", 1, true), nil)
end

T["Jupyter notebooks"]["return no content when they cannot be parsed"] = function()
  h.eq(notebook.format("not json"), nil)
end

return T
