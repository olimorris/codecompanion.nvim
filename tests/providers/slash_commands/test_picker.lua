local h = require("tests.helpers")

local child = MiniTest.new_child_neovim()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        picker = require("codecompanion.providers.slash_commands.picker")
        require("mini.pick").setup()

        OUTPUT = {}
        function make_slash_command(opts)
          return {
            config = { opts = opts or {} },
            output = function(_, item)
              table.insert(OUTPUT, item)
            end,
          }
        end

        function open_picker(providers, SlashCommand)
          vim.schedule(function()
            providers.mini_pick(SlashCommand)
          end)
        end

        function get_source()
          return MiniPick.get_picker_opts().source
        end
      ]])
    end,
    post_once = child.stop,
  },
})

T["Picker"] = MiniTest.new_set()

T["Picker"]["list outputs every marked item"] = function()
  child.lua([[
    open_picker(picker.build_list_pickers({
      prompt = "Select tools",
      empty_message = "No tools",
      preview = false,
      items = function()
        return { { name = "grep_search" }, { name = "read_file", description = "Read a file" } }
      end,
    }), make_slash_command())
  ]])

  local names = child.lua([[
    local source = get_source()
    source.choose_marked(source.items)
    MiniPick.stop()

    return vim.tbl_map(function(item)
      return item.name
    end, OUTPUT)
  ]])

  h.eq({ "grep_search", "read_file" }, names)
end

T["Picker"]["list sends the selection to a custom output"] = function()
  child.lua([[
    CUSTOM = {}
    open_picker(picker.build_list_pickers({
      prompt = "Select a cached URL",
      empty_message = "No cached URLs",
      preview = false,
      output = function(_, item)
        table.insert(CUSTOM, item.url)
      end,
      items = function()
        return { { name = "1 hour ago", url = "https://neovim.io" } }
      end,
    }), make_slash_command())
  ]])

  local result = child.lua([[
    local source = get_source()
    source.choose(source.items[1])
    MiniPick.stop()

    return { custom = CUSTOM, output = OUTPUT }
  ]])

  h.eq({ "https://neovim.io" }, result.custom)
  h.eq({}, result.output)
end

T["Picker"]["files outputs a path relative to the cwd"] = function()
  child.lua([[open_picker(picker.build_file_pickers({ prompt = "Select file(s)" }), make_slash_command())]])

  local result = child.lua([[
    get_source().choose(vim.fn.getcwd() .. "/./lua/codecompanion/health.lua")
    MiniPick.stop()

    return { output = OUTPUT[1], cwd = vim.fn.getcwd() }
  ]])

  h.eq({
    path = result.cwd .. "/lua/codecompanion/health.lua",
    relative_path = "lua/codecompanion/health.lua",
  }, result.output)
end

T["Picker"]["files searches the cwd AND every configured directory"] = function()
  child.lua([[
    local root = vim.fn.tempname()
    vim.fn.mkdir(root .. "/project", "p")
    vim.fn.mkdir(root .. "/notes", "p")
    vim.fn.writefile({}, root .. "/project/init.lua")
    vim.fn.writefile({}, root .. "/notes/todo.md")
    vim.cmd.cd(root .. "/project")

    open_picker(
      picker.build_file_pickers({ prompt = "Select file(s)" }),
      make_slash_command({ dirs = { root .. "/notes", root .. "/missing" } })
    )
  ]])

  local result = child.lua([[
    local items = vim.tbl_map(function(path)
      return vim.fn.fnamemodify(path, ":t")
    end, get_source().items)
    MiniPick.stop()

    table.sort(items)
    return items
  ]])

  h.eq({ "init.lua", "todo.md" }, result)
end

return T
