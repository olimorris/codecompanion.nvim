---
description: The prompt library enables you to use pre-built prompts, in markdown, in CodeCompanion. Learn how to configure it here
---

# Configuring the Prompt Library

CodeCompanion enables you to leverage prompt templates to quickly interact with your codebase. These prompts can be the built-in ones or custom-built. CodeCompanion uses a prompt library to manage and organize these prompts.

> [!IMPORTANT]
> Prompts can be pure Lua tables, residing in your configuration, or markdown files stored in your filesystem.

## Adding Prompts

> [!NOTE]
> See the [Creating Prompts](#creating-prompts) section to learn how to create your own.

There are two ways to add prompts to the prompt library. You can either define them directly in your configuration file as Lua tables, or you can store them as markdown files in your filesystem and reference them in your configuration.

::: tabs

== Lua

```lua
require("codecompanion").setup({
  prompt_library = {
    ["Docusaurus"] = {
      strategy = "chat",
      description = "Write documentation for me",
      prompts = {
        {
          role = "user",
          content = [[Just some prompt that will write docs for me.]],
        },
      },
    },
  },
})
```

== Markdown

```lua
require("codecompanion").setup({
  prompt_library = {
    markdown = {
      dirs = {
        vim.fn.getcwd() .. "/.prompts", -- Can be relative
        "~/.dotfiles/.config/prompts", -- Or absolute paths
      },
    },
  }
})
```

:::

## Creating Prompts

As mentioned earlier, prompts can be created in two ways: as Lua tables or as markdown files.

> [!NOTE]
> Markdown prompts are new in `v18.0.0`. They provide a cleaner, more maintainable way to define prompts with support for external Lua files for dynamic content.

### Basic Structure

At their core, prompts define a series of messages sent to an LLM. Let's start with a simple example:

::: tabs

== Markdown

````markdown
---
name: Explain Code
strategy: chat
description: Explain how code works
---

## system

You are an expert programmer who excels at explaining code clearly and concisely.

## user

Please explain the following code:

```${context.filetype}
${shared.code}
```
````

== Lua

````lua
require("codecompanion").setup({
  prompt_library = {
    ["Explain Code"] = {
      strategy = "chat",
      description = "Explain how code works",
      prompts = {
        {
          role = "system",
          content = "You are an expert programmer who excels at explaining code clearly and concisely.",
        },
        {
          role = "user",
          content = function(context)
            local text = require("codecompanion.helpers.actions").get_code(context.start_line, context.end_line)
            return "Please explain the following code:\n\n```" .. context.filetype .. "\n" .. text .. "\n```"
          end,
        },
      },
    },
  },
})
````

:::

#### Markdown Format

Markdown prompts consist of two main parts:

1. **Frontmatter** - YAML metadata between `---` delimiters that defines the prompt's configuration
2. **Prompt sections** - Markdown headings (`## system`, `## user`) that define the role and content of each message

**Required frontmatter fields:**
- `name` - The display name in the Action Palette
- `description` - Description shown in the Action Palette
- `strategy` - The strategy to use (`chat`, `inline`, `workflow`)

**Optional frontmatter fields:**
- `opts` - Additional options (see [Options](#options) section)
- `context` - Pre-loaded context (see [Prompts with Context](#prompts-with-context) section)

**Prompt sections:**
- `## system` - System messages that set the LLM's behaviour
- `## user` - User messages containing your requests

### Options

Both markdown and Lua prompts support a wide range of options to customise behaviour:

::: tabs

== Markdown

````markdown
---
name: Generate Tests
strategy: inline
description: Generate unit tests
opts:
  alias: tests
  auto_submit: true
  modes:
    - v
  placement: new
  stop_context_insertion: true
---

## system

Generate comprehensive unit tests for the provided code.

## user

```${context.filetype}
${shared.code}
```
````

== Lua

````lua
["Generate Tests"] = {
  strategy = "inline",
  description = "Generate unit tests",
  opts = {
    alias = "tests",
    auto_submit = true,
    modes = { "v" },
    placement = "new",
    stop_context_insertion = true,
  },
  prompts = {
    {
      role = "system",
      content = "Generate comprehensive unit tests for the provided code.",
    },
    {
      role = "user",
      content = function(context)
        local text = require("codecompanion.helpers.actions").get_code(context.start_line, context.end_line)
        return "```" .. context.filetype .. "\n" .. text .. "\n```"
      end,
    },
  },
}
````

:::

**Common options:**

- `adapter` - Specify a different adapter/model:

::: tabs

== Markdown

````markdown
---
name: My Prompt
strategy: chat
description: Uses a specific model
opts:
  adapter:
    name: ollama
    model: deepseek-coder:6.7b
---
````

== Lua

````lua
opts = {
  adapter = {
    name = "ollama",
    model = "deepseek-coder:6.7b",
  },
}
````

:::

- `alias` - Allows the prompt to be triggered via `:CodeCompanion /{alias}`
- `auto_submit` - Automatically submit the prompt to the LLM
- `default_rules` - Specify a default rule group to load with the prompt
- `ignore_system_prompt` - Don't send the default system prompt with the request
- `intro_message` - Custom intro message for the chat buffer UI
- `is_slash_cmd` - Make the prompt available as a slash command in chat
- `modes` - Only show in specific modes (`{ "v" }` for visual mode)
- `placement` - For inline strategy: `new`, `replace`, `add`, `before`, `chat`
- `pre_hook` - Function to run before the prompt is executed (Lua only)
- `stop_context_insertion` - Prevent automatic context insertion
- `user_prompt` - Get user input before actioning the response

### Using Placeholders

Placeholders allow you to inject dynamic content into your prompts. In markdown prompts, use `${placeholder.name}` syntax:

#### Context Placeholders

The `context` object contains information about the current buffer:

::: tabs

== Markdown

````markdown
---
name: Buffer Info
strategy: chat
description: Show buffer information
---

## user

I'm working in buffer ${context.bufnr} which is a ${context.filetype} file.
````

== Lua

````lua
["Buffer Info"] = {
  strategy = "chat",
  description = "Show buffer information",
  prompts = {
    {
      role = "user",
      content = function(context)
        return "I'm working in buffer " .. context.bufnr .. " which is a " .. context.filetype .. " file."
      end,
    },
  },
}
````

:::

**Available context fields:**

````lua
{
  bufnr = 7,
  buftype = "",
  cursor_pos = { 10, 3 },
  end_col = 3,
  end_line = 10,
  filetype = "lua",
  is_normal = false,
  is_visual = true,
  lines = { "local function fire_autocmd(status)", "..." },
  mode = "V",
  start_col = 1,
  start_line = 8,
  winnr = 1000
}
````

#### External Lua Files

For markdown prompts, you can reference functions and values from external Lua files placed in the same directory as your prompt. This is useful for complex logic or reusable components:

**Example directory structure:**
````
.prompts/
├── commit.md
├── commit.lua
├── shared.lua
└── utils.lua
````

**shared.lua:**
````lua
return {
  code = function(args)
    local actions = require("codecompanion.helpers.actions")
    return actions.get_code(args.context.start_line, args.context.end_line)
  end,
}
````

**commit.lua:**
````lua
return {
  diff = function(args)
    return vim.system({ "git", "diff", "--no-ext-diff", "--staged" }, { text = true }):wait().stdout
  end,
}
````

**commit.md:**
````markdown
---
name: Commit message
strategy: chat
description: Generate a commit message
opts:
  alias: commit
---

## user

You are an expert at following the Conventional Commit specification. Given the git diff listed below, please generate a commit message for me:

```diff
${commit.diff}
```
````

In this example, `${commit.diff}` references the `diff` function from `commit.lua`. The plugin automatically:

1. Detects the dot notation (`commit.`)
2. Loads `commit.lua` from the same directory
3. Calls the `diff` function
4. Replaces `${commit.diff}` with the result

**Multiple files example:**

````markdown
---
name: Code Review
strategy: chat
description: Review code changes
---

## user

Please review this code:

```${context.filetype}
${shared.code}
```

Here's the git diff:

```diff
${utils.git_diff}
```
````

This prompt can reference functions from both `shared.lua` and `utils.lua` in the same directory.

**Function signature:**

External Lua functions receive an `args` table:

````lua
return {
  my_function = function(args)
    -- args.context - Buffer context
    -- args.item - The full prompt item
    return "some value"
  end,
  static_value = "I'm just a string",
}
````

#### Built-in Helpers

You can also reference built-in values using dot notation:

- `${context.bufnr}` - Current buffer number
- `${context.filetype}` - Current filetype
- `${context.start_line}` - Visual selection start
- `${context.end_line}` - Visual selection end

And many more from the context object.

### Advanced Example

Here's a complete example showing the power of markdown prompts:

**unit_tests.md:**
````markdown
---
name: Unit tests
strategy: inline
description: Generate unit tests for the selected code
opts:
  alias: tests
  auto_submit: true
  modes:
    - v
  placement: new
  stop_context_insertion: true
---

## system

When generating unit tests, follow these steps:

1. Identify the programming language.
2. Identify the purpose of the function or module to be tested.
3. List the edge cases and typical use cases that should be covered in the tests and share the plan with the user.
4. Generate unit tests using an appropriate testing framework for the identified programming language.
5. Ensure the tests cover:
      - Normal cases
      - Edge cases
      - Error handling (if applicable)
6. Provide the generated unit tests in a clear and organized manner without additional explanations or chat.

## user

Please generate unit tests for this code from buffer ${context.bufnr}:

```${context.filetype}
${shared.code}
```
````

**shared.lua:**
````lua
return {
  code = function(args)
    local actions = require("codecompanion.helpers.actions")
    return actions.get_code(args.context.start_line, args.context.end_line)
  end,
}
````

This prompt:
- Only appears in visual mode
- Automatically submits to the LLM
- Places results in a new buffer
- Uses a reusable `shared.code` function
- Includes detailed instructions for the LLM

### Why Markdown?

Markdown prompts offer several advantages:

- **Cleaner syntax** - No Lua string escaping or concatenation
- **Better readability** - Natural formatting with proper indentation
- **Easier editing** - Edit in any markdown editor with syntax highlighting
- **Reusability** - Share Lua helper files across multiple prompts
- **Version control friendly** - Easier to diff and review changes

For complex prompts with multiple messages or dynamic content, markdown files are significantly easier to maintain than Lua tables.

## Advanced Configuration

### Conditionals

**Lua only:**

You can conditionally control when prompts appear in the Action Palette or conditionally include specific prompt messages using `condition` functions:

**Item-level conditions** (controls visibility in Action Palette):

````lua
["Open chats ..."] = {
  name = "Open chats ...",
  strategy = " ",
  description = "Your currently open chats",
  condition = function(context)
    return #require("codecompanion").buf_get_chat() > 0
  end,
  picker = {
    ---
  }
}
````

**Prompt-level conditions** (controls individual messages):

````lua
["Visual Only"] = {
  strategy = "chat",
  description = "Only appears in visual mode",
  prompts = {
    {
      role = "user",
      content = "This prompt only appears when you're in visual mode.",
      condition = function(context)
        return context.is_visual
      end,
    },
  },
}
````

> [!NOTE]
> Conditionals are not supported in markdown prompts since they require Lua functions. Use the `modes` option in frontmatter instead to control visibility by mode.

### Prompts with Context

Pre-load a chat buffer with context from files, symbols, or URLs:

::: tabs

== Markdown

````markdown
---
name: Test Context
strategy: chat
description: Add some context
context:
  - type: file
    path:
      - lua/codecompanion/health.lua
      - lua/codecompanion/http.lua
  - type: symbols
    path: lua/codecompanion/strategies/chat/init.lua
  - type: url
    url: https://raw.githubusercontent.com/olimorris/codecompanion.nvim/refs/heads/main/lua/codecompanion/commands.lua
---

## user

I'll think of something clever to put here...
````

== Lua

````lua
["Test Context"] = {
  strategy = "chat",
  description = "Add some context",
  context = {
    {
      type = "file",
      path = {
        "lua/codecompanion/health.lua",
        "lua/codecompanion/http.lua",
      },
    },
    {
      type = "symbols",
      path = "lua/codecompanion/strategies/chat/init.lua",
    },
    {
      type = "url",
      url = "https://raw.githubusercontent.com/olimorris/codecompanion.nvim/refs/heads/main/lua/codecompanion/commands.lua",
    },
  },
  prompts = {
    {
      role = "user",
      content = "I'll think of something clever to put here...",
      opts = {
        contains_code = true,
      },
    },
  },
}
````

:::

Context items appear at the top of the chat buffer. URLs are automatically cached for you.

### Using Pre-hooks

Pre-hooks allow you to run custom logic before a prompt is executed. This is particularly useful for creating new buffers or setting up the environment:

**Lua only:**

````lua
["Boilerplate HTML"] = {
  strategy = "inline",
  description = "Generate some boilerplate HTML",
  opts = {
    ---@return number
    pre_hook = function()
      local bufnr = vim.api.nvim_create_buf(true, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_set_option_value("filetype", "html", { buf = bufnr })
      return bufnr
    end,
  },
  prompts = {
    {
      role = "system",
      content = "You are an expert HTML programmer",
    },
    {
      role = "user",
      content = "Please generate some HTML boilerplate for me. Return the code only and no markdown codeblocks",
    },
  },
}
````

For the inline strategy, the plugin will detect a number being returned from the `pre_hook` and assume that is the buffer number you wish any code to be streamed into.









