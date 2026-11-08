local h = require("tests.helpers")

local new_set = MiniTest.new_set
local child = MiniTest.new_child_neovim()

local T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        vim.env.REX_SESSION = "session:test"
        _G.reports = {}
        vim.api.nvim_ui_send = function(content)
          table.insert(_G.reports, content)
        end
        fire = require("codecompanion.utils").fire
        require("codecompanion.integrations.rex").setup()
      ]])
    end,
    post_once = child.stop,
  },
})

---@param events { event: string, data: table }[]
---@return string[]
local function fire_and_get_reports(events)
  return child.lua(
    [[
    for _, entry in ipairs(...) do
      fire(entry.event, entry.data)
    end
    return _G.reports
  ]],
    { events }
  )
end

---@param text string
---@return string
local function encode(text)
  return vim.base64.encode(text)
end

T["Rex"] = new_set()

T["Rex"]["reports each chat as its own record"] = function()
  local reports = fire_and_get_reports({
    { event = "ChatCreated", data = { bufnr = 3 } },
    { event = "ChatSubmitted", data = { bufnr = 3 } },
    { event = "ChatCreated", data = { bufnr = 7 } },
  })

  h.eq({
    "\027]7501;id=codecompanion/3:state=idle:app=codecompanion\027\\",
    "\027]7501;id=codecompanion/3:state=working:app=codecompanion\027\\",
    "\027]7501;id=codecompanion/7:state=idle:app=codecompanion\027\\",
  }, reports)
end

T["Rex"]["reports a chat as blocked on an approval and working once it's given"] = function()
  local reports = fire_and_get_reports({
    { event = "ChatSubmitted", data = { bufnr = 3 } },
    { event = "ToolApprovalRequested", data = { bufnr = 3, name = "run_command" } },
    { event = "ToolApprovalFinished", data = { bufnr = 3 } },
  })

  h.eq(
    "\027]7501;id=codecompanion/3:state=blocked:app=codecompanion:kind=permission:msg="
      .. encode("Approval needed: run_command")
      .. "\027\\",
    reports[2]
  )
  h.eq("\027]7501;id=codecompanion/3:state=working:app=codecompanion\027\\", reports[3])
end

T["Rex"]["DOES NOT resume a chat that ISN'T blocked"] = function()
  local reports = fire_and_get_reports({
    { event = "ChatDone", data = { bufnr = 3 } },
    { event = "ToolApprovalFinished", data = { bufnr = 3 } },
  })

  h.eq({ "\027]7501;id=codecompanion/3:state=done:app=codecompanion\027\\" }, reports)
end

T["Rex"]["re-reports a chat's state when its title is set"] = function()
  child.lua([[
    require("codecompanion.interactions.chat").buf_get_chat = function()
      return { title = _G.chat_title }
    end
  ]])
  fire_and_get_reports({ { event = "ChatSubmitted", data = { bufnr = 3 } } })
  child.lua([[_G.chat_title = "Fix the login flow"]])
  local reports = fire_and_get_reports({
    { event = "ChatTitle", data = { bufnr = 3, title = "Fix the login flow" } },
    { event = "ChatTitle", data = { bufnr = 7, title = "Refactor the parser" } },
  })

  h.eq({
    "\027]7501;id=codecompanion/3:state=working:app=codecompanion\027\\",
    "\027]7501;id=codecompanion/3:state=working:app=codecompanion:title=" .. encode("Fix the login flow") .. "\027\\",
  }, reports)
end

T["Rex"]["clears a chat's record when it's closed"] = function()
  local reports = fire_and_get_reports({
    { event = "ChatCreated", data = { bufnr = 3 } },
    { event = "ChatClosed", data = { bufnr = 3 } },
    { event = "ChatClosed", data = { bufnr = 3 } },
  })

  h.eq({
    "\027]7501;id=codecompanion/3:state=idle:app=codecompanion\027\\",
    "\027]7501;id=codecompanion/3:state=clear\027\\",
  }, reports)
end

T["Rex"]["clears every record when Neovim exits"] = function()
  fire_and_get_reports({
    { event = "ChatCreated", data = { bufnr = 3 } },
    { event = "ChatCreated", data = { bufnr = 7 } },
  })
  child.lua([[vim.api.nvim_exec_autocmds("VimLeavePre", {})]])

  h.eq("\027]7501;id=codecompanion:state=clear\027\\", child.lua_get("_G.reports[#_G.reports]"))
end

T["Rex"]["keeps a message on one line and WITHIN the size limit"] = function()
  -- The 21 byte prefix puts the 2048 byte limit halfway through a two byte character
  local reports = fire_and_get_reports({
    { event = "ToolQuestionAsked", data = { bufnr = 3, header = "Which\nfiles" .. string.rep("é", 1100) } },
  })

  local message = vim.base64.decode(reports[1]:match("msg=([^:]+)\027\\$"))
  h.eq("Question: Which files", message:sub(1, 21))
  h.eq(2047, #message)
  h.eq("é", message:sub(-2))
end

T["Rex"]["DOES NOT report OUTSIDE of Rex"] = function()
  child.lua([[
    _G.reports = {}
    vim.env.REX_SESSION = nil
    vim.api.nvim_clear_autocmds({ group = "codecompanion.integrations.rex" })
    require("codecompanion.integrations.rex").setup()
  ]])

  h.eq({}, fire_and_get_reports({ { event = "ChatCreated", data = { bufnr = 3 } } }))
end

return T
