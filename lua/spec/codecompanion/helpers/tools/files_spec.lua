local assert = require("luassert")
local files = require("codecompanion.strategies.chat.tools.files")

describe("File tools", function()
  it("can create a file", function()
    local path = "~/tmp/test.txt"
    files.actions.create({ path = path, contents = "Hello World" })

    local file = io.open(vim.fn.expand(path), "r")
    assert.not_nil(file)
    local contents = file:read("*a")
    assert.are.same("Hello World", contents)
    file:close()
  end)

  it("can read a file", function()
    local path = "~/tmp/test.txt"
    local output = files.actions.read({ path = path })

    assert.are.same("Hello World", output.content)
  end)

  it("can edit a file", function()
    local path = "~/tmp/test.txt"
    files.actions.edit({ path = path, contents = "Hello CodeCompanion" })

    local file = io.open(vim.fn.expand(path), "r")
    local contents = file:read("*a")
    assert.are.same("Hello CodeCompanion", contents)
    file:close()
  end)

  it("can rename a file", function()
    local path = "~/tmp/test.txt"
    local new_path = "~/tmp/test_new.txt"
    files.actions.rename({ path = path, new_path = new_path })

    local file = io.open(vim.fn.expand(path), "r")
    assert.is_nil(file)

    file = io.open(vim.fn.expand(new_path), "r")
    assert.not_nil(file)
    file:close()

    os.remove(vim.fn.expand(new_path))
  end)

  it("can move a file", function()
    local path = "~/tmp/test.txt"
    local new_path = "~/tmp/test_new.txt"
    files.actions.create({ path = path, contents = "Hello World" })

    files.actions.move({ path = path, new_path = new_path })

    local file = io.open(vim.fn.expand(path), "r")
    assert.is_nil(file)

    file = io.open(vim.fn.expand(new_path), "r")
    assert.not_nil(file)
    file:close()

    os.remove(vim.fn.expand(new_path))
  end)

  it("can delete a file", function()
    local path = "~/tmp/test.txt"
    files.actions.create({ path = path, contents = "Hello World" })

    files.actions.delete({ path = path })

    local file = io.open(vim.fn.expand(path), "r")
    assert.is_nil(file)

    os.remove(vim.fn.expand("~/tmp"))
  end)
end)
