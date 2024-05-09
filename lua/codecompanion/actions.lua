local config = require("codecompanion.config")
local utils = require("codecompanion.utils.util")

local M = {}

M.static = {}

local expert = function(filetype)
  return "I want you to act as a senior "
    .. filetype
    .. " developer. I will give you specific code examples and ask you questions. I want you to advise me with explanations and code examples."
end

local send_code = function(context)
  local text = require("codecompanion.helpers.code").get_code(context.start_line, context.end_line)

  return "I have the following code:\n\n```" .. context.filetype .. "\n" .. text .. "\n```\n\n"
end

M.validate = function(items, context)
  local validated_items = {}
  local mode = context.mode:lower()

  for _, item in ipairs(items) do
    if item.condition and type(item.condition) == "function" then
      if item.condition(context) then
        table.insert(validated_items, item)
      end
    elseif item.opts and item.opts.modes then
      if utils.contains(item.opts.modes, mode) then
        table.insert(validated_items, item)
      end
    else
      table.insert(validated_items, item)
    end
  end

  return validated_items
end

M.static.actions = {
  {
    name = "Chat",
    strategy = "chat",
    description = "Open/restore a chat buffer to converse with "
      .. config.options.strategies.chat:gsub("^%l", string.upper),
    type = nil,
    prompts = {
      n = function()
        return require("codecompanion").chat()
      end,
      v = {
        {
          role = "system",
          content = function(context)
            return "I want you to act as a senior "
              .. context.filetype
              .. " developer. I will give you specific code examples and ask you questions. I want you to advise me with explanations and code examples."
          end,
        },
        {
          role = "user",
          contains_code = true,
          content = function(context)
            return send_code(context)
          end,
        },
      },
    },
  },
  {
    name = "Open chats ...",
    strategy = "chat",
    description = "Your currently open chats",
    condition = function()
      return _G.codecompanion_chats and utils.count(_G.codecompanion_chats) > 0
    end,
    picker = {
      prompt = "Select a chat",
      items = function()
        local ui = require("codecompanion.utils.ui")
        local chats = {}

        for bufnr, chat in pairs(_G.codecompanion_chats) do
          table.insert(chats, {
            name = chat.name,
            strategy = "chat",
            description = chat.description,
            callback = function()
              _G.codecompanion_chats[bufnr] = nil

              if config.options.display.chat.type == "float" then
                ui.open_float(bufnr, {
                  display = config.options.display.chat.float_options,
                })
              else
                vim.api.nvim_set_current_buf(bufnr)
              end

              ui.buf_scroll_to_end(bufnr)
            end,
          })
        end

        return chats
      end,
    },
  },
  {
    name = "Chat as ...",
    strategy = "chat",
    description = "Open a chat buffer, acting as a specific persona",
    picker = {
      prompt = "Chat as a persona",
      items = {
        {
          name = "JavaScript",
          strategy = "chat",
          description = "Chat as a senior JavaScript developer",
          type = "javascript",
          prompts = {
            {
              role = "system",
              content = expert("JavaScript"),
            },
            {
              role = "user",
              contains_code = true,
              condition = function(context)
                return context.is_visual
              end,
              content = function(context)
                return send_code(context)
              end,
            },
            {
              role = "user",
              condition = function(context)
                return not context.is_visual
              end,
              content = "\n \n",
            },
          },
        },
        {
          name = "Lua",
          strategy = "chat",
          description = "Chat as a senior Lua developer",
          type = "lua",
          prompts = {
            {
              role = "system",
              content = expert("Lua"),
            },
            {
              role = "user",
              contains_code = true,
              condition = function(context)
                return context.is_visual
              end,
              content = function(context)
                return send_code(context)
              end,
            },
            {
              role = "user",
              condition = function(context)
                return not context.is_visual
              end,
              content = "\n \n",
            },
          },
        },
        {
          name = "PHP",
          strategy = "chat",
          description = "Chat as a senior PHP developer",
          type = "php",
          prompts = {
            {
              role = "system",
              content = expert("PHP"),
            },
            {
              role = "user",
              contains_code = true,
              condition = function(context)
                return context.is_visual
              end,
              content = function(context)
                return send_code(context)
              end,
            },
            {
              role = "user",
              condition = function(context)
                return not context.is_visual
              end,
              content = "\n \n",
            },
          },
        },
        {
          name = "Python",
          strategy = "chat",
          description = "Chat as a senior Python developer",
          type = "python",
          prompts = {
            {
              role = "system",
              content = expert("Python"),
            },
            {
              role = "user",
              contains_code = true,
              condition = function(context)
                return context.is_visual
              end,
              content = function(context)
                return send_code(context)
              end,
            },
            {
              role = "user",
              condition = function(context)
                return not context.is_visual
              end,
              content = "\n \n",
            },
          },
        },
        {
          name = "Ruby",
          strategy = "chat",
          description = "Chat as a senior Ruby developer",
          type = "ruby",
          prompts = {
            {
              role = "system",
              content = expert("Ruby"),
            },
            {
              role = "user",
              contains_code = true,
              condition = function(context)
                return context.is_visual
              end,
              content = function(context)
                return send_code(context)
              end,
            },
            {
              role = "user",
              condition = function(context)
                return not context.is_visual
              end,
              content = "\n \n",
            },
          },
        },
        {
          name = "Rust",
          strategy = "chat",
          description = "Chat as a senior Rust developer",
          type = "rust",
          prompts = {
            {
              role = "system",
              content = expert("Rust"),
            },
            {
              role = "user",
              contains_code = true,
              condition = function(context)
                return context.is_visual
              end,
              content = function(context)
                return send_code(context)
              end,
            },
            {
              role = "user",
              condition = function(context)
                return not context.is_visual
              end,
              content = "\n \n",
            },
          },
        },
      },
    },
  },
  {
    name = "Tools",
    strategy = "tools",
    description = "Use the built-in tools to help you code",
    opts = {
      enabled = config.options.tools.enabled,
      modes = { "n" },
    },
    prompts = {
      {
        role = "system",
        content = function()
          return [[You have a selection of tools available to you which will aid you in responding to my questions. These tools allow you to trigger commands on my machine. Once triggered, I will then share the output of the command back to you, giving you the ability to revise your answer or perhaps trigger additional tools and commands.

This may be useful for testing code you've written or for doing mathematical calculations. In order for you to trigger a tool, the request must then be placed within an xml code block. Below is a perfect example of how to do this:

The tools available to you, and their config:

- `code_runner` - This tool allows you to execute code on my machine. The code and language must be specified as inputs. For example:

```xml
<tool>
  <name>code_runner</name>
  <parameters>
    <inputs>
      <!-- Choose the language to run -->
      <!-- Currently you can only choose python or ruby -->
      <lang>python</lang>
      <!-- Anything within the code tag will be executed -->
      <code>print("Hello World")</code>
      <!-- The version of the lang to use -->
      <version>3.11.0</version>
    </inputs>
  </parameters>
</tool>
```

You can use the code runner to solve math problems by writing Python code. However, please don't hypothesise or guess the output in your response.

Note: Here are some REALLY IMPORTANT things to note:

1. If you wish to trigger multiple tools, place them after one another in the codeblock. The order in which you place them will be the order in which they're executed.
2. Not every question I ask of you will require the use of a tool.
]]
        end,
      },
      {
        role = "user",
        content = "\n \n",
      },
    },
  },
  {
    name = "Agentic Workflows ...",
    strategy = "chat",
    description = "Workflows to improve the performance of your LLM",
    picker = {
      prompt = "Select a workflow",
      items = {
        {
          name = "Code a feature - Outline, draft, consider and then revise",
          callback = function(context)
            local agent = require("codecompanion.agent")
            return agent
              .new({
                context = context,
                strategy = "chat",
              })
              :workflow({
                {
                  role = "system",
                  content = "You carefully provide accurate, factual, thoughtful, nuanced answers, and are brilliant at reasoning. If you think there might not be a correct answer, you say so. Always spend a few sentences explaining background context, assumptions, and step-by-step thinking BEFORE you try to answer a question. Don't be verbose in your answers, but do provide details and examples where it might help the explanation. You are an expert software engineer for the "
                    .. context.filetype
                    .. " language.",
                  start = true,
                },
                {
                  condition = function()
                    return context.is_visual
                  end,
                  contains_code = true,
                  role = "user",
                  content = "Here is some relevant context: " .. send_code(context),
                  start = true,
                },
                {
                  role = "user",
                  content = "I want you to help me code a feature. Before we write any code let's outline how we'll architect and implement the feature with the context you already have. The feature I'd like to add is ",
                  start = true,
                },
                {
                  role = "user",
                  content = "Thanks. Now let's draft the code for the feature.",
                  auto_submit = true,
                },
                {
                  role = "user",
                  content = "Great. Now let's consider the code. I'd like you to check it carefully for correctness, style, and efficiency, and give constructive criticism for how to improve it.",
                  auto_submit = true,
                },
                {
                  role = "user",
                  content = "Thanks. Now let's revise the code based on the feedback, without additional explanations.",
                  auto_submit = true,
                },
              })
          end,
        },
        {
          name = "Refactor some code - Outline, draft, consider and then revise",
          callback = function(context)
            local agent = require("codecompanion.agent")
            return agent
              .new({
                context = context,
                strategy = "chat",
              })
              :workflow({
                {
                  role = "system",
                  content = "You carefully provide accurate, factual, thoughtful, nuanced answers, and are brilliant at reasoning. If you think there might not be a correct answer, you say so. Always spend a few sentences explaining background context, assumptions, and step-by-step thinking BEFORE you try to answer a question. Don't be verbose in your answers, but do provide details and examples where it might help the explanation. You are an expert software engineer for the "
                    .. context.filetype
                    .. " language.",
                  start = true,
                },
                {
                  condition = function()
                    return context.is_visual
                  end,
                  contains_code = true,
                  role = "user",
                  content = "Here is some relevant context: " .. send_code(context),
                  start = true,
                },
                {
                  role = "user",
                  content = "I want you to help me with a refactor. Before we write any code let's outline how we'll architect and implement the code with the context you already have. What I'm looking to achieve is ",
                  start = true,
                },
                {
                  role = "user",
                  content = "Thanks. Now let's draft the code for the refactor.",
                  auto_submit = true,
                },
                {
                  role = "user",
                  content = "Great. Now let's consider the code. I'd like you to check it carefully for correctness, style, and efficiency, and give constructive criticism for how to improve it.",
                  auto_submit = true,
                },
                {
                  role = "user",
                  content = "Thanks. Now let's revise the code based on the feedback, without additional explanations.",
                  auto_submit = true,
                },
              })
          end,
        },
      },
    },
  },
  {
    name = "Inline code ...",
    strategy = "inline",
    description = "Get "
      .. config.options.strategies.inline:gsub("^%l", string.upper)
      .. " to write/refactor code for you",
    picker = {
      prompt = "Select an inline code action",
      items = {
        {
          name = "Custom",
          strategy = "inline",
          description = "Custom user input",
          opts = {
            user_prompt = true,
            -- Placement should be determined
          },
          prompts = {
            {
              role = "system",
              content = function(context)
                if context.buftype == "terminal" then
                  return "I want you to act as an expert in writing terminal commands that will work for my current shell "
                    .. os.getenv("SHELL")
                    .. ". I will ask you specific questions and I want you to return the raw command only (no codeblocks and explanations). If you can't respond with a command, respond with nothing"
                end
                return "I want you to act as a senior "
                  .. context.filetype
                  .. " developer. I will ask you specific questions and I want you to return raw code only (no codeblocks and no explanations). If you can't respond with code, respond with nothing"
              end,
            },
          },
        },
        {
          name = "/doc",
          strategy = "inline",
          description = "Add a documentation comment",
          opts = {
            modes = { "v" },
            placement = "before", -- cursor|before|after|replace|new
          },
          prompts = {
            {
              role = "system",
              content = function(context)
                return "You are an expert coder and helpful assistant who can help write documentation comments for the "
                  .. context.filetype
                  .. " language"
              end,
            },
            {
              role = "user",
              contains_code = true,
              content = function(context)
                return send_code(context)
              end,
            },
            {
              role = "user",
              content = "Please add a documentation comment to the provided code and reply with just the comment only and no explanation, no codeblocks and do not return the code either. If neccessary add parameter and return types",
            },
          },
        },
        {
          name = "/optimize",
          strategy = "inline",
          description = "Optimize the selected code",
          opts = {
            modes = { "v" },
            placement = "replace",
          },
          prompts = {
            {
              role = "system",
              content = function(context)
                return "You are an expert coder and helpful assistant who can help optimize code for the "
                  .. context.filetype
                  .. " language"
              end,
            },
            {
              role = "user",
              contains_code = true,
              content = function(context)
                return send_code(context)
              end,
            },
            {
              role = "user",
              content = "Please optimize the provided code. Please just respond with the code only and no explanation or markdown block syntax",
            },
          },
        },
        {
          name = "/test",
          strategy = "inline",
          description = "Create unit tests for the selected code",
          opts = {
            modes = { "v" },
            placement = "new",
          },
          prompts = {
            {
              role = "system",
              content = function(context)
                return "You are an expert coder and helpful assistant who can help write unit tests for the "
                  .. context.filetype
                  .. " language"
              end,
            },
            {
              role = "user",
              contains_code = true,
              content = function(context)
                return send_code(context)
              end,
            },
            {
              role = "user",
              content = "Please create a unit test for the provided code. Please just respond with the code only and no explanation or markdown block syntax",
            },
          },
        },
      },
    },
  },
  {
    name = "Code advisor",
    strategy = "chat",
    description = "Get advice on the code you've selected",
    opts = {
      modes = { "v" },
      auto_submit = true,
      user_prompt = true,
    },
    prompts = {
      {
        role = "system",
        content = function(context)
          return "I want you to act as a senior "
            .. context.filetype
            .. " developer. I will ask you specific questions and I want you to return concise explanations and codeblock examples."
        end,
      },
      {
        role = "user",
        contains_code = true,
        content = function(context)
          return send_code(context)
        end,
      },
    },
  },
  {
    name = "LSP assistant",
    strategy = "chat",
    description = "Get help from OpenAI to fix LSP diagnostics",
    opts = {
      modes = { "v" },
      auto_submit = true, -- Automatically submit the chat
      user_prompt = false, -- Prompt the user for their own input
    },
    prompts = {
      {
        role = "system",
        content = [[You are an expert coder and helpful assistant who can help debug code diagnostics, such as warning and error messages. When appropriate, give solutions with code snippets as fenced codeblocks with a language identifier to enable syntax highlighting.]],
      },
      {
        role = "user",
        content = function(context)
          local diagnostics =
            require("codecompanion.helpers.lsp").get_diagnostics(context.start_line, context.end_line, context.bufnr)

          local concatenated_diagnostics = ""
          for i, diagnostic in ipairs(diagnostics) do
            concatenated_diagnostics = concatenated_diagnostics
              .. i
              .. ". Issue "
              .. i
              .. "\n  - Location: Line "
              .. diagnostic.line_number
              .. "\n  - Severity: "
              .. diagnostic.severity
              .. "\n  - Message: "
              .. diagnostic.message
              .. "\n"
          end

          return "The programming language is "
            .. context.filetype
            .. ". This is a list of the diagnostic messages:\n\n"
            .. concatenated_diagnostics
        end,
      },
      {
        role = "user",
        contains_code = true,
        content = function(context)
          return "This is the code, for context:\n\n"
            .. "```"
            .. context.filetype
            .. "\n"
            .. require("codecompanion.helpers.code").get_code(
              context.start_line,
              context.end_line,
              { show_line_numbers = true }
            )
            .. "\n```\n\n"
        end,
      },
    },
  },
  {
    name = "Load saved chats ...",
    strategy = "saved_chats",
    description = "Load your previously saved chats",
    condition = function()
      local saved_chats = require("codecompanion.strategies.saved_chats")
      return saved_chats:has_chats()
    end,
    picker = {
      prompt = "Load chats",
      items = function()
        local saved_chats = require("codecompanion.strategies.saved_chats")
        local items = saved_chats:list({ sort = true })

        local chats = {}

        for _, chat in pairs(items) do
          table.insert(chats, {
            name = chat.tokens,
            strategy = chat.filename,
            description = chat.dir,
            callback = function()
              return saved_chats
                .new({
                  filename = chat.filename,
                })
                :load(chat)
            end,
          })
        end

        return chats
      end,
    },
  },
}

return M
