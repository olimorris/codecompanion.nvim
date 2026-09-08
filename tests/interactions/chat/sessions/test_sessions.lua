local h = require("tests.helpers")

local new_set = MiniTest.new_set
local T = new_set()

local child = MiniTest.new_child_neovim()
T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        codecompanion = require("codecompanion")
        h = require('tests.helpers')
        _G.chat, _G.tools = h.setup_chat_buffer()

        _G.sessions = require("codecompanion.interactions.chat.sessions")
        _G.storage = require("codecompanion.interactions.chat.sessions.storage")
        _G.serializer = require("codecompanion.interactions.chat.sessions.serializer")

        _G.session_dir = vim.fn.tempname()
        require("codecompanion.config").interactions.chat.sessions.dir = _G.session_dir

        _G.build_session = function()
          local chat = _G.chat
          chat.cycle = 3
          chat.settings = { temperature = 0.5 }
          chat.tool_registry:add("weather")
          chat.tool_registry:add("test_group")
          chat.context:add({ source = "test", name = "file", id = "<file>init.lua</file>" })
          table.insert(chat.messages, { role = "user", content = "Hello there" })
          table.insert(chat.messages, { role = "llm", content = "General Kenobi" })

          _G.sessions.save(chat, { title = "Fixing the parser" })
          return _G.storage.list()[1].stem
        end
      ]])
    end,
    post_case = function()
      child.lua([[
        vim.fn.delete(_G.session_dir, "rf")
        h.teardown_chat_buffer()
      ]])
    end,
    post_once = child.stop,
  },
})

T["Sessions"] = new_set()

T["Sessions"]["a saved chat round-trips through disk"] = function()
  child.lua([[
    local stem = _G.build_session()
    local restored = _G.sessions.load(stem)

    _G.result = {
      title = restored.title,
      cycle = restored.cycle,
      adapter = restored.adapter.name,
      saved_settings = vim.json.decode(table.concat(vim.fn.readfile(_G.storage.path(stem, "chat")), "\n")).settings,
      messages = vim.tbl_map(function(message)
        return { role = message.role, content = message.content }
      end, restored.messages),
      context_items = vim.tbl_map(function(item)
        return item.id
      end, restored.context_items),
      in_use = vim.tbl_keys(restored.tool_registry.in_use),
      groups = vim.tbl_keys(restored.tool_registry.groups),
      schemas = vim.tbl_keys(restored.tool_registry.schemas),
    }
    table.sort(_G.result.in_use)
    table.sort(_G.result.schemas)
  ]])

  local result = child.lua_get([[_G.result]])

  h.eq("Fixing the parser", result.title)
  h.eq(3, result.cycle)
  h.eq({ temperature = 0.5 }, result.saved_settings)
  h.eq("test_adapter", result.adapter)

  local last_two = { result.messages[#result.messages - 1], result.messages[#result.messages] }
  h.eq({ role = "user", content = "Hello there" }, last_two[1])
  h.eq({ role = "llm", content = "General Kenobi" }, last_two[2])

  h.expect_contains("<file>init.lua</file>", table.concat(result.context_items, ","))

  h.eq({ "func", "weather" }, result.in_use)
  h.eq({ "test_group" }, result.groups)
  h.eq({ "<tool>func</tool>", "<tool>weather</tool>" }, result.schemas)
end

T["Sessions"]["restores the buffer from the saved markdown"] = function()
  child.lua([[
    local stem = _G.build_session()
    _G.saved_lines = vim.api.nvim_buf_get_lines(_G.chat.bufnr, 0, -1, false)
    _G.restored_lines = vim.api.nvim_buf_get_lines(_G.sessions.load(stem).bufnr, 0, -1, false)
  ]])

  h.eq(child.lua_get([[_G.saved_lines]]), child.lua_get([[_G.restored_lines]]))
end

T["Sessions"]["DROPS every rendered context block but the last"] = function()
  child.lua([[
    local stem = _G.build_session()
    vim.fn.writefile({
      "## foo",
      "",
      "> Context:",
      "> - <file>old.lua</file>",
      "",
      "First question",
      "",
      "## foo",
      "",
      "> Context:",
      "> - <file>current.lua</file>",
      "",
      "Second question",
    }, _G.storage.path(stem, "ui"))

    _G.lines = vim.api.nvim_buf_get_lines(_G.sessions.load(stem).bufnr, 0, -1, false)
  ]])

  h.eq({
    "## foo",
    "",
    "First question",
    "",
    "## foo",
    "",
    "> Context:",
    "> - <file>current.lua</file>",
    "",
    "Second question",
    "",
  }, child.lua_get([[_G.lines]]))
end

T["Sessions"]["DOES NOT treat a context block inside a code fence as one"] = function()
  child.lua([[
    local stem = _G.build_session()
    vim.fn.writefile({
      "## foo",
      "",
      "Here is what my chat buffer looks like:",
      "",
      "````markdown",
      "> Context:",
      "> - <file>pasted.lua</file>",
      "````",
      "",
      "> Context:",
      "> - <file>current.lua</file>",
      "",
      "Second question",
    }, _G.storage.path(stem, "ui"))

    _G.lines = table.concat(vim.api.nvim_buf_get_lines(_G.sessions.load(stem).bufnr, 0, -1, false), "\n")
  ]])

  h.expect_contains("<file>pasted.lua</file>", child.lua_get([[_G.lines]]))
  h.expect_contains("<file>current.lua</file>", child.lua_get([[_G.lines]]))
end

T["Sessions"]["DROPS a tool that is no longer configured"] = function()
  child.lua([[
    local stem = _G.build_session()
    require("codecompanion.config").interactions.chat.tools.weather = nil

    local restored = _G.sessions.load(stem)
    _G.in_use = vim.tbl_keys(restored.tool_registry.in_use)
  ]])

  h.eq({ "func" }, child.lua_get([[_G.in_use]]))
end

T["Sessions"]["a restored chat carries its history into the next request"] = function()
  child.lua([[
    local stem = _G.build_session()
    local restored = _G.sessions.load(stem)

    vim.api.nvim_buf_set_lines(restored.bufnr, -1, -1, false, { "## foo", "", "And what happened next?" })
    h.send_to_llm(restored, "It got better")

    _G.turns = {}
    for _, message in ipairs(restored.messages) do
      if message.role ~= "system" then
        table.insert(_G.turns, message.role .. ": " .. message.content)
      end
    end
  ]])

  h.eq({
    "user: Hello there",
    "llm: General Kenobi",
    "user: And what happened next?",
    "llm: It got better",
  }, child.lua_get([[_G.turns]]))
end

T["Sessions"]["autosaves an untitled chat after its first response"] = function()
  child.lua([[
    table.insert(_G.chat.messages, { role = "user", content = "Why does the parser drop the last message?" })
    h.send_to_llm(_G.chat, "Because it expects a re-parse")

    _G.listed = _G.storage.list()
  ]])

  local listed = child.lua_get([[_G.listed]])
  h.eq(1, #listed)
  h.eq("Why does the parser drop the last message?", listed[1].meta.title)
end

T["Sessions"]["autosave DOES NOT give the chat a title of its own"] = function()
  child.lua([[
    table.insert(_G.chat.messages, { role = "user", content = "Why does the parser drop the last message?" })
    h.send_to_llm(_G.chat, "Because it expects a re-parse")

    _G.title = _G.chat.title
    _G.saved_title = _G.storage.list()[1].meta.title
  ]])

  h.eq(vim.NIL, child.lua_get([[_G.title]]))
  h.eq("Why does the parser drop the last message?", child.lua_get([[_G.saved_title]]))
end

T["Sessions"]["DOES NOT autosave when the option is off"] = function()
  child.lua([[
    require("codecompanion.config").interactions.chat.sessions.autosave = false
    table.insert(_G.chat.messages, { role = "user", content = "Why does the parser drop the last message?" })
    h.send_to_llm(_G.chat, "Because it expects a re-parse")

    _G.listed = _G.storage.list()
  ]])

  h.eq(0, #child.lua_get([[_G.listed]]))
end

T["Sessions"]["truncates a long first message on a word boundary"] = function()
  child.lua([[
    table.insert(_G.chat.messages, {
      role = "user",
      content = "Why is the sessions serializer dropping tool schemas on restore?",
    })
    h.send_to_llm(_G.chat, "Because they are re-resolved from config")

    _G.title = _G.storage.list()[1].meta.title
  ]])

  h.eq("Why is the sessions serializer dropping tool", child.lua_get([[_G.title]]))
end

T["Sessions"]["KEEPS a saved session up to date when continuous_save is on"] = function()
  child.lua([[
    local stem = _G.build_session()
    h.send_to_llm(_G.chat, "It got better")
    _G.saved = table.concat(vim.fn.readfile(_G.storage.path(stem, "chat")), "\n")
  ]])

  h.expect_contains("It got better", child.lua_get([[_G.saved]]))
end

T["Sessions"]["DOES NOT update a saved session when continuous_save is off"] = function()
  child.lua([[
    require("codecompanion.config").interactions.chat.sessions.continuous_save = false
    local stem = _G.build_session()
    h.send_to_llm(_G.chat, "It got better")
    _G.saved = table.concat(vim.fn.readfile(_G.storage.path(stem, "chat")), "\n")
  ]])

  h.expect_not_contains("It got better", child.lua_get([[_G.saved]]))
end

T["Sessions"]["restores the session chosen in the picker"] = function()
  child.lua([[
    _G.build_session()
    vim.ui.select = function(choices, _, on_choice)
      _G.choices = choices
      on_choice(choices[1], 1)
    end

    _G.sessions.select({ on_restored = function(chat) _G.restored_title = chat.title end })
  ]])

  h.expect_match(child.lua_get([[_G.choices]])[1], "^%(%d+%a+ ago%) Fixing the parser$")
  h.eq("Fixing the parser", child.lua_get([[_G.restored_title]]))
end

T["Sessions"]["falls back to the default adapter when the saved one has gone"] = function()
  child.lua([[
    _G.args = _G.serializer.to_chat_args({ adapter = "adapter_that_went_away", messages = {} })
  ]])

  h.eq("test_adapter", child.lua_get([[_G.args.adapter]]))
end

T["Sessions"]["restores the model the session was saved with"] = function()
  child.lua([[
    _G.args = _G.serializer.to_chat_args({ adapter = "test_adapter", model = "gpt-4o", messages = {} })
  ]])

  h.eq("gpt-4o", child.lua_get([[_G.args.adapter.model.name]]))
end

T["Sessions"]["the listing follows a session that is saved again"] = function()
  child.lua([[
    local stem = _G.build_session()
    _G.before = _G.storage.list()[1].meta.saved_at

    local session = _G.storage.read(stem)
    session.meta.saved_at = _G.before + 3600
    _G.storage.write(stem, session)

    _G.after = _G.storage.list()[1].meta.saved_at
  ]])

  h.eq(3600, child.lua_get([[_G.after]]) - child.lua_get([[_G.before]]))
end

T["Sessions"]["the listing follows a session written by another Neovim instance"] = function()
  child.lua([[
    _G.build_session()
    _G.before = #_G.storage.list()

    local meta = { schema_version = _G.serializer.SCHEMA_VERSION, title = "Written elsewhere", created_at = 1 }
    vim.fn.writefile({ vim.json.encode(meta) }, _G.storage.path("19700101T000001-written-elsewhere", "meta"))

    _G.after = #_G.storage.list()
  ]])

  h.eq(1, child.lua_get([[_G.before]]))
  h.eq(2, child.lua_get([[_G.after]]))
end

T["Sessions"]["REJECTS a session written by a newer schema"] = function()
  child.lua([[
    local stem = _G.build_session()
    local path = _G.storage.path(stem, "meta")
    local meta = vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
    meta.schema_version = _G.serializer.SCHEMA_VERSION + 1
    vim.fn.writefile({ vim.json.encode(meta) }, path)

    _G.session = _G.storage.read(stem)
  ]])

  h.eq(vim.NIL, child.lua_get([[_G.session]]))
end

T["Sessions"]["truncates a long title on a word boundary"] = function()
  child.lua([[
    _G.slug = require("codecompanion.interactions.chat.sessions.utils.slug").slugify(
      "Figuring out why the parser drops the last message when restoring a session"
    )
  ]])

  h.eq("figuring-out-why-the-parser-drops-the-last-message", child.lua_get([[_G.slug]]))
end

return T
