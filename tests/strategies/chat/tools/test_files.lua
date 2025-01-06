local files = require("codecompanion.strategies.chat.tools.files")

local h = require("tests.helpers")

describe("File tools", function()
  it("can create a file", function()
    local path = "~/tmp/test.txt"
    files.actions.create({ path = path, contents = "Hello World" })

    local file = io.open(vim.fn.expand(path), "r")
    h.not_eq(file, nil)
    local contents = file:read("*a")
    h.eq("Hello World", contents)
    file:close()
  end)

  it("can read a file", function()
    local path = "~/tmp/test.txt"
    local output = files.actions.read({ path = path })

    h.eq("Hello World", output.content)
  end)

  it("can edit a file", function()
    local path = "~/tmp/test.txt"
    files.actions.edit({ path = path, search = "Hello World", replace = "Hello CodeCompanion" })

    local file = io.open(vim.fn.expand(path), "r")
    local contents = file:read("*a")
    h.eq("Hello CodeCompanion", contents)
    file:close()
  end)

  it("can rename a file", function()
    local path = "~/tmp/test.txt"
    local new_path = "~/tmp/test_new.txt"
    files.actions.rename({ path = path, new_path = new_path })

    local file = io.open(vim.fn.expand(path), "r")
    h.eq(file, nil)

    file = io.open(vim.fn.expand(new_path), "r")
    h.not_eq(file, nil)
    file:close()

    os.remove(vim.fn.expand(new_path))
  end)

  it("can move a file", function()
    local path = "~/tmp/test.txt"
    local new_path = "~/tmp/test_new.txt"
    files.actions.create({ path = path, contents = "Hello World" })

    files.actions.move({ path = path, new_path = new_path })

    local file = io.open(vim.fn.expand(path), "r")
    h.eq(file, nil)

    file = io.open(vim.fn.expand(new_path), "r")
    h.not_eq(file, nil)
    file:close()

    os.remove(vim.fn.expand(new_path))
  end)

  it("can delete a file", function()
    local path = "~/tmp/test.txt"
    files.actions.create({ path = path, contents = "Hello World" })

    files.actions.delete({ path = path })

    local file = io.open(vim.fn.expand(path), "r")
    h.eq(file, nil)

    os.remove(vim.fn.expand("~/tmp"))
  end)
end)
