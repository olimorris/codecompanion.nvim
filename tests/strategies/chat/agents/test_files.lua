local files = require("codecompanion.strategies.chat.agents.tools.files")

local h = require("tests.helpers")

describe("File tools", function()
  it("can create a file", function()
    local path = "~/tmp/test.txt"
    files.actions.create({ path = path, contents = "Hello World" })

    local file = io.open(vim.fs.normalize(path), "r")
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

  it("can read lines of a file", function()
    local path = vim.fn.tempname()
    files.actions.create({
      path = path,
      contents = [[This is line 1
This is line 2
This is line 3
This is line 4
This is line 5]],
    })

    local output = files.actions.read_lines({
      path = path,
      start_line = 2,
      end_line = 4,
    })

    local lines = vim.split(output.content, "\n")

    h.eq("2:  This is line 2", lines[1])
    h.eq("3:  This is line 3", lines[#lines - 1])
    h.eq("4:  This is line 4", lines[#lines])
  end)

  it("can edit a file", function()
    local path = "~/tmp/test.txt"
    files.actions.edit({ path = path, search = "Hello World", replace = "Hello CodeCompanion" })

    local file = io.open(vim.fs.normalize(path), "r")
    local contents = file:read("*a")
    h.eq("Hello CodeCompanion", contents)
    file:close()
  end)

  it("can rename a file", function()
    local path = "~/tmp/test.txt"
    local new_path = "~/tmp/test_new.txt"
    files.actions.rename({ path = path, new_path = new_path })

    local file = io.open(vim.fs.normalize(path), "r")
    h.eq(file, nil)

    file = io.open(vim.fs.normalize(new_path), "r")
    h.not_eq(file, nil)
    file:close()

    os.remove(vim.fs.normalize(new_path))
  end)

  it("can move a file", function()
    local path = "~/tmp/test.txt"
    local new_path = "~/tmp/test_new.txt"
    files.actions.create({ path = path, contents = "Hello World" })

    files.actions.move({ path = path, new_path = new_path })

    local file = io.open(vim.fs.normalize(path), "r")
    h.eq(file, nil)

    file = io.open(vim.fs.normalize(new_path), "r")
    h.not_eq(file, nil)
    file:close()

    os.remove(vim.fs.normalize(new_path))
  end)

  it("can delete a file", function()
    local path = "~/tmp/test.txt"
    files.actions.create({ path = path, contents = "Hello World" })

    files.actions.delete({ path = path })

    local file = io.open(vim.fs.normalize(path), "r")
    h.eq(file, nil)

    os.remove(vim.fs.normalize("~/tmp"))
  end)
end)
