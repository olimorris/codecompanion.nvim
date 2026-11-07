local h = require("tests.helpers")

local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()
local T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        _G.sequences = {}
        _G.titles = {}
        vim.api.nvim_ui_send = function(sequence)
          local title = sequence:match("^\027%]2;(.*)\027\\$")
          if title then
            table.insert(_G.titles, title)
          else
            table.insert(_G.sequences, sequence)
          end
        end

        _G.start_herdr = function(env)
          for name, value in pairs(env) do
            vim.env[name] = value
          end
          require("codecompanion.integrations.herdr").setup()
        end

        _G.fire = function(event, bufnr, data)
          vim.api.nvim_exec_autocmds("User", {
            pattern = "CodeCompanion" .. event,
            data = vim.tbl_extend("force", { bufnr = bufnr }, data or {}),
          })
        end
      ]])
    end,
    post_once = child.stop,
  },
})

T["herdr app"] = new_set()

T["herdr app"]["reports done when a turn finishes"] = function()
  child.lua([[
    start_herdr({ HC_TERMINAL_ID = "t9" })
    local bufnr = vim.api.nvim_create_buf(false, true)
    fire("ChatCreated", bufnr)
    fire("ChatSubmitted", bufnr)
    fire("ChatDone", bufnr)
  ]])

  h.eq({
    "\027]7501;state=idle:app=codecompanion\027\\",
    "\027]7501;state=working:app=codecompanion\027\\",
    "\027]7501;state=done:app=codecompanion\027\\",
  }, child.lua_get("_G.sequences"))
end

T["herdr app"]["reports the kind of block and resumes working"] = function()
  child.lua([[
    start_herdr({ HC_TERMINAL_ID = "t9" })
    local bufnr = vim.api.nvim_create_buf(false, true)
    fire("ChatSubmitted", bufnr)
    fire("ToolApprovalRequested", bufnr, { name = "run_command" })
    fire("ToolApprovalFinished", bufnr)
    fire("ToolQuestionAsked", bufnr, { header = "Scope" })
  ]])

  h.eq({
    "\027]7501;state=working:app=codecompanion\027\\",
    "\027]7501;state=blocked:kind=permission:app=codecompanion\027\\",
    "\027]7501;state=working:app=codecompanion\027\\",
    "\027]7501;state=blocked:kind=question:app=codecompanion\027\\",
  }, child.lua_get("_G.sequences"))
end

T["herdr app"]["a blocked chat outranks a working one"] = function()
  child.lua([[
    start_herdr({ HC_TERMINAL_ID = "t9" })
    local blocked = vim.api.nvim_create_buf(false, true)
    local working = vim.api.nvim_create_buf(false, true)
    fire("ChatSubmitted", blocked)
    fire("ToolApprovalRequested", blocked)
    fire("ChatSubmitted", working)
  ]])

  h.eq({
    "\027]7501;state=working:app=codecompanion\027\\",
    "\027]7501;state=blocked:kind=permission:app=codecompanion\027\\",
  }, child.lua_get("_G.sequences"))
end

T["herdr app"]["clears the report when the last chat closes"] = function()
  child.lua([[
    start_herdr({ HC_TERMINAL_ID = "t9" })
    local bufnr = vim.api.nvim_create_buf(false, true)
    fire("ChatCreated", bufnr)
    fire("ChatClosed", bufnr)
  ]])

  h.eq({
    "\027]7501;state=idle:app=codecompanion\027\\",
    "\027]7501;state=clear\027\\",
  }, child.lua_get("_G.sequences"))
end

T["herdr app"]["leaves a herdr pane INSIDE the app to the herdr CLI"] = function()
  child.lua([[
    start_herdr({ HC_TERMINAL_ID = "t9", HERDR_ENV = "1", HERDR_PANE_ID = "p1", HERDR_BIN_PATH = "true" })
    local bufnr = vim.api.nvim_create_buf(false, true)
    fire("ChatSubmitted", bufnr)
  ]])

  h.eq({}, child.lua_get("_G.sequences"))
end

T["herdr app"]["names the pane after the chat title and clears it on close"] = function()
  child.lua([[
    start_herdr({ HC_TERMINAL_ID = "t9" })
    local bufnr = vim.api.nvim_create_buf(false, true)
    fire("ChatCreated", bufnr)
    fire("ChatTitle", bufnr, { title = "Fix the login flow" })
    fire("ChatClosed", bufnr)
  ]])

  h.eq({ "Fix the login flow", "" }, child.lua_get("_G.titles"))
end

T["herdr app"]["names an untitled chat after the branch"] = function()
  child.lua([[
    local repo = vim.fn.tempname()
    vim.fn.mkdir(repo, "p")
    vim.system({ "git", "init", "-q", "-b", "fix-login", repo }):wait()
    vim.fn.chdir(repo)

    start_herdr({ HC_TERMINAL_ID = "t9" })
    fire("ChatCreated", vim.api.nvim_create_buf(false, true))
    vim.wait(2000, function()
      return #_G.titles > 0
    end)
  ]])

  h.eq({ "CodeCompanion [fix-login]" }, child.lua_get("_G.titles"))
end

T["herdr app"]["DOES NOT set the title when Neovim's 'title' is ON"] = function()
  child.lua([[
    vim.o.title = true
    start_herdr({ HC_TERMINAL_ID = "t9" })
    local bufnr = vim.api.nvim_create_buf(false, true)
    fire("ChatCreated", bufnr)
    fire("ChatTitle", bufnr, { title = "Fix the login flow" })
  ]])

  h.eq({}, child.lua_get("_G.titles"))
end

return T
