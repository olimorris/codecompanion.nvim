local h = require("tests.helpers")

local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()

local T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        _G.TEST_CWD = vim.fn.tempname()
        _G.MEMORY_DIR = vim.fs.joinpath(_G.TEST_CWD, "memories")
        vim.fn.mkdir(_G.MEMORY_DIR, "p")

        -- Set up while the tests directory is still on the package path
        h = require("tests.helpers")
        _G.chat = h.setup_chat_buffer()

        vim.uv.chdir(_G.TEST_CWD)
      ]])
    end,
    post_case = function()
      child.lua([[
        pcall(vim.fn.delete, _G.TEST_CWD, "rf")
        h.teardown_chat_buffer()
      ]])
    end,
    post_once = child.stop,
  },
})

local function add_memories()
  child.lua([[
    vim.fn.mkdir(vim.fs.joinpath(_G.MEMORY_DIR, "projects"), "p")
    vim.fn.writefile({ "Sub-agents" }, vim.fs.joinpath(_G.MEMORY_DIR, "parallel-sub-agents.md"))
    vim.fn.writefile({ "Zsh" }, vim.fs.joinpath(_G.MEMORY_DIR, "projects", "dotfiles-zsh-migration.md"))
  ]])
end

T["Memory"] = new_set()

T["Memory"]["indexes nested memories as paths the tool accepts back"] = function()
  add_memories()

  h.eq({
    "/memories/parallel-sub-agents.md",
    "/memories/projects/dotfiles-zsh-migration.md",
  }, child.lua([[return require("codecompanion.memory").get_index()]]))
end

T["Memory"]["prompt lists every memory"] = function()
  add_memories()

  local prompt = child.lua([[return require("codecompanion.memory").get_prompt()]])

  h.expect_match(prompt, "%- /memories/parallel%-sub%-agents%.md")
  h.expect_match(prompt, "%- /memories/projects/dotfiles%-zsh%-migration%.md")
  h.expect_match(prompt, "That index is complete")
end

T["Memory"]["prompt says the directory is empty when there are no memories"] = function()
  local prompt = child.lua([[return require("codecompanion.memory").get_prompt()]])

  h.expect_match(prompt, "Your memory directory `/memories` is empty")
  h.expect_match(prompt, "Name a memory so that the file name alone says what it holds")
end

T["Memory"]["refreshing picks up a memory created since the prompt was built"] = function()
  local contents = child.lua([[
    _G.chat.tool_registry:add("memory", { config = require("codecompanion.config").interactions.chat.tools })
    vim.fn.writefile({ "Sub-agents" }, vim.fs.joinpath(_G.MEMORY_DIR, "parallel-sub-agents.md"))

    require("codecompanion.memory").refresh_prompt(_G.chat)

    return table.concat(
      vim.tbl_map(function(message)
        return message.content
      end, _G.chat.messages),
      "\n"
    )
  ]])

  h.expect_match(contents, "%- /memories/parallel%-sub%-agents%.md")
end

return T
