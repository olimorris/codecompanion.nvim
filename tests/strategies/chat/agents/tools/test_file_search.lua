local h = require("tests.helpers")

local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()
local T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        -- Setup test directory structure
        _G.TEST_DIR = 'tests/stubs/file_search'
        _G.TEST_DIR_ABSOLUTE = vim.fs.joinpath(vim.fn.tempname(), _G.TEST_DIR)

        -- Create test directory structure
        vim.fn.mkdir(_G.TEST_DIR_ABSOLUTE .. '/src/components', 'p')
        vim.fn.mkdir(_G.TEST_DIR_ABSOLUTE .. '/src/utils', 'p')
        vim.fn.mkdir(_G.TEST_DIR_ABSOLUTE .. '/tests', 'p')
        vim.fn.mkdir(_G.TEST_DIR_ABSOLUTE .. '/docs', 'p')

        -- Create test files
        local test_files = {
          'src/components/Button.js',
          'src/components/Modal.ts',
          'src/components/Header.jsx',
          'src/utils/helpers.js',
          'src/utils/validators.ts',
          'src/index.js',
          'tests/button.test.js',
          'tests/modal.test.ts',
          'docs/README.md',
          'package.json',
          'config.yaml'
        }

        for _, file in ipairs(test_files) do
          local filepath = vim.fs.joinpath(_G.TEST_DIR_ABSOLUTE, file)
          vim.fn.writefile({'test content'}, filepath)
        end

        h = require('tests.helpers')
        chat, agent = h.setup_chat_buffer()

        -- Change to test directory for relative path testing
        vim.cmd('cd ' .. _G.TEST_DIR_ABSOLUTE)
      ]])
    end,
    post_case = function()
      child.lua([[
        h.teardown_chat_buffer()
      ]])
    end,
    post_once = child.stop,
  },
})

T["returns results"] = function()
  child.lua([[
    local tool = {
      {
        ["function"] = {
          name = "file_search",
          arguments = '{"query": "**/Button.js"}'
        },
      },
    }
    agent:execute(chat, tool)
  ]])

  local output = child.lua_get("chat.messages[#chat.messages].content")
  h.eq(
    "<fileSearchTool>Searched files for `**/Button.js`, 1 results\n```\nsrc/components/Button.js\n```</fileSearchTool>",
    output
  )
end

T["can search for JavaScript files"] = function()
  child.lua([[
    local tool = {
      {
        ["function"] = {
          name = "file_search",
          arguments = '{"query": "**/*.js"}'
        },
      },
    }
    agent:execute(chat, tool)
  ]])

  local output = child.lua_get("chat.messages[#chat.messages].content")
  h.eq("Button.js", string.match(output, "Button%.js"))
  h.eq("helpers.js", string.match(output, "helpers%.js"))
  h.eq("index.js", string.match(output, "index%.js"))
  h.eq("button.test.js", string.match(output, "button%.test%.js"))

  -- Should not match TypeScript files
  h.not_eq("Modal.ts", string.match(output, "Modal%.ts"))
end

T["can search for TypeScript files"] = function()
  child.lua([[
    local tool = {
      {
        ["function"] = {
          name = "file_search",
          arguments = '{"query": "**/*.ts"}'
        },
      },
    }
    agent:execute(chat, tool)
  ]])

  local output = child.lua_get("chat.messages[#chat.messages].content")
  h.eq("Modal.ts", string.match(output, "Modal%.ts"))
  h.eq("validators.ts", string.match(output, "validators%.ts"))
  h.eq("modal.test.ts", string.match(output, "modal%.test%.ts"))

  -- Should not match JavaScript files
  h.not_eq("Button.js", string.match(output, "Button%.js"))
end

T["can search for multiple file extensions"] = function()
  child.lua([[
     local tool = {
       {
         ["function"] = {
           name = "file_search",
           arguments = '{"query": "**/*.{js,ts}"}'
         },
       },
     }
     agent:execute(chat, tool)
   ]])

  local output = child.lua_get("chat.messages[#chat.messages].content")

  -- Should match both JS and TS files
  h.eq("Button.js", string.match(output, "Button%.js"))
  h.eq("Modal.ts", string.match(output, "Modal%.ts"))
  h.eq("validators.ts", string.match(output, "validators%.ts"))

  -- Should not match other extensions
  h.not_eq("Header.jsx", string.match(output, "Header%.jsx"))
  h.not_eq("README.md", string.match(output, "README%.md"))
end

T["can search in specific directories"] = function()
  child.lua([[
    local tool = {
      {
        ["function"] = {
          name = "file_search",
          arguments = '{"query": "src/components/*"}'
        },
      },
    }
    agent:execute(chat, tool)
  ]])

  local output = child.lua_get("chat.messages[#chat.messages].content")
  h.eq("Button.js", string.match(output, "Button%.js"))
  h.eq("Modal.ts", string.match(output, "Modal%.ts"))
  h.eq("Header.jsx", string.match(output, "Header%.jsx"))

  -- Should not match files outside components directory
  h.not_eq("helpers.js", string.match(output, "helpers%.js"))
  h.not_eq("index.js", string.match(output, "index%.js"))
end

T["can search for test files"] = function()
  child.lua([[
    local tool = {
      {
        ["function"] = {
          name = "file_search",
          arguments = '{"query": "**/*.test.*"}'
        },
      },
    }
    agent:execute(chat, tool)
  ]])

  local output = child.lua_get("chat.messages[#chat.messages].content")
  h.eq("button.test.js", string.match(output, "button%.test%.js"))
  h.eq("modal.test.ts", string.match(output, "modal%.test%.ts"))

  -- Should not match non-test files
  h.not_eq("Button.js", string.match(output, "Button%.js"))
  h.not_eq("Modal.ts", string.match(output, "Modal%.ts"))
end

T["handles empty search results"] = function()
  child.lua([[
    local tool = {
      {
        ["function"] = {
          name = "file_search",
          arguments = '{"query": "**/*.nonexistent"}'
        },
      },
    }
    agent:execute(chat, tool)
  ]])

  local output = child.lua_get("chat.messages[#chat.messages].content")
  h.eq("<fileSearchTool>Searched files for `**/*.nonexistent`, no results</fileSearchTool>", output)
end

T["handles empty query"] = function()
  child.lua([[
     local tool = {
       {
         ["function"] = {
           name = "file_search",
           arguments = '{"query": ""}'
         },
       },
     }
     agent:execute(chat, tool)
   ]])

  local output = child.lua_get("chat.messages[#chat.messages].content")
  h.expect_contains("Searched files for ``, error:", output)
end

T["respects max_results parameter"] = function()
  child.lua([[
     local tool = {
       {
         ["function"] = {
           name = "file_search",
           arguments = '{"query": "**/*", "max_results": 3}'
         },
       },
     }
     agent:execute(chat, tool)
   ]])

  -- Count the number of files in the output
  local file_count = child.lua([[
     local output = chat.messages[#chat.messages].content
     local count = 0
     -- Count occurrences of file extensions or common file patterns
     for line in output:gmatch("[^\n]+") do
       if line:match("%.%w+$") then -- Lines ending with file extensions
         count = count + 1
       end
     end
     return count
   ]])

  h.eq(true, file_count <= 3)
end

T["can search for specific file names"] = function()
  child.lua([[
     local tool = {
       {
         ["function"] = {
           name = "file_search",
           arguments = '{"query": "**/package.json"}'
         },
       },
     }
     agent:execute(chat, tool)
   ]])

  local output = child.lua_get("chat.messages[#chat.messages].content")

  h.eq("package.json", string.match(output, "package%.json"))

  -- Should not match other files
  h.not_eq("config.yaml", string.match(output, "config%.yaml"))
end

T["can return no files"] = function()
  child.lua([[
     local tool = {
       {
         ["function"] = {
           name = "file_search",
           arguments = '{"query": "src/**/test*"}'
         },
       },
     }
     agent:execute(chat, tool)
   ]])

  local output = child.lua_get("chat.messages[#chat.messages].content")

  h.eq("<fileSearchTool>Searched files for `src/**/test*`, no results</fileSearchTool>", output)
end

return T
