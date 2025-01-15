# Creating Prompts

The purpose of this guide is to showcase how you can extend the functionality of CodeCompanion by adding your own prompts to the config that are reflected in the _Action Palette_. The _Action Palette_ is a lua table which is parsed by the plugin and displayed as a `vim.ui.select` component. By specifying certain keys, the behaviour of the table can be customised further.

## Adding a prompt to the palette

A prompt can be added via the `setup` function:

```lua
require("codecompanion").setup({
  prompt_library = {
    ["My New Prompt"] = {
      strategy = "chat",
      description = "Some cool custom prompt you can do",
      prompts = {
        {
          role = "system",
          content = "You are an experienced developer with Lua and Neovim",
        },
        {
          role = "user",
          content = "Can you explain why ..."
        }
      },
    }
  }
})
```

In this example, if you run `:CodeCompanionActions`, you should see "My New Prompt" in the bottom of the _Prompts_ section of the palette. Clicking on your new action will initiate the _chat_ strategy and set the value of the chat buffer based on the _role_ and _content_ that's been specified in the prompt.

In the following sections, we'll explore how you can customise your prompts even more.

## Recipe #1: Creating boilerplate code

### Boilerplate HTML

As the years go by, I find myself writing less and less HTML. So when it comes to quickly scaffolding out a HTML page, I inevitably turn to a search engine. It would be great if I could have an action that could quickly generate some boilerplate HTML from the _Action Palette_.

Let's take a look at how we can achieve that:

```lua
require("codecompanion").setup({
  prompt_library = {
    ["Boilerplate HTML"] = {
      strategy = "inline",
      description = "Generate some boilerplate HTML",
      opts = {
        mapping = "<LocalLeader>ch"
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
    },
  },
})
```

Nice! We've used some careful prompting to ensure that we get HTML boilerplate back from the LLM. Oh...and notice that I added a key map too!

### Leveraging pre-hooks

To make this example complete, we can leverage a pre-hook to create a new buffer and set the filetype to be html:

```lua
{
  ["Boilerplate HTML"] = {
    strategy = "inline",
    description = "Generate some boilerplate HTML",
    opts = {
      pre_hook = function()
        local bufnr = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_buf_set_option(bufnr, "filetype", "html")
        vim.api.nvim_set_current_buf(bufnr)
        return bufnr
      end
    }
    ---
  }
}
```

For the inline strategy, the plugin will detect a number being returned from the `pre_hook` and assume that is the buffer number you wish any code to be streamed into.

### Conclusion

Whilst this example was useful at demonstrating the functionality of the _Action Palette_ and your custom prompts, it's not using LLMs to add any real value to your workflow (this boilerplate could be a snippet after all!). So let's step things up in the next section.

## Recipe #2: Using context in your prompts

Now let's look at how we can use an LLM to advise us on some code that we have visually selected in a buffer. Infact, this very example used to be builtin to the plugin as the _Code Advisor_ action:

```lua
require("codecompanion").setup({
  prompt_library = {
    ["Code Expert"] = {
      strategy = "chat",
      description = "Get some special advice from an LLM",
      opts = {
        mapping = "<LocalLeader>ce",
        modes = { "v" },
        short_name = "expert",
        auto_submit = true,
        stop_context_insertion = true,
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
          content = function(context)
            local text = require("codecompanion.helpers.actions").get_code(context.start_line, context.end_line)

            return "I have the following code:\n\n```" .. context.filetype .. "\n" .. text .. "\n```\n\n"
          end,
          opts = {
            contains_code = true,
          }
        },
      },
    },
  },
})
```

At first glance there's a lot of new stuff in this. Let's break it down.

### Palette options

```lua
opts = {
  mapping = "<LocalLeader>ce",
  modes = { "v" },
  short_name = "expert",
  auto_submit = true,
  stop_context_insertion = true,
  user_prompt = true,
},
```

In the `opts` table we're specifying that we only want this action to appear in the _Action Palette_ if we're in visual mode. We're also asking the chat strategy to automatically submit the prompts to the LLM via the `auto_submit = true` value. We're also telling the picker that we want to get the user's input before we action the response with `user_prompt = true`. With the `short_name = "expert"` option, the user can run `:CodeCompanion /expert` from the cmdline in order to trigger this prompt. Finally, as we define a prompt to add any visually selected text to the chat buffer, we need to add the `stop_context_insertion = true` option to prevent the chat buffer from duplicating this. Remember that visually selecting text and opening a chat buffer will result in that selection from being adding as a codeblock.

### Prompt options and context

In the example below you can see how we've structured the prompts to get advice on the code:

```lua
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
    content = function(context)
      local text = require("codecompanion.helpers.actions").get_code(context.start_line, context.end_line)

      return "I have the following code:\n\n```" .. context.filetype .. "\n" .. text .. "\n```\n\n"
    end,
    opts = {
      contains_code = true,
    }
  },
},
```

One of the most useful features of the custom prompts is the ability to receive context about the current buffer and any lines of code we've selected. An example context table looks like:

```lua
{
  bufnr = 7,
  buftype = "",
  cursor_pos = { 10, 3 },
  end_col = 3,
  end_line = 10,
  filetype = "lua",
  is_normal = false,
  is_visual = true,
  lines = { "local function fire_autocmd(status)", '  vim.api.nvim_exec_autocmds("User", { pattern = "CodeCompanionInline", data = { status = status } })', "end" },
  mode = "V",
  start_col = 1,
  start_line = 8,
  winnr = 1000
}
```

Using the context above, our first prompt then makes more sense:

```lua
{
  role = "system",
  content = function(context)
    return "I want you to act as a senior "
      .. context.filetype
      .. " developer. I will ask you specific questions and I want you to return concise explanations and codeblock examples."
  end,
},
```

We are telling the LLM to act as a "senior _Lua_ developer" based on the filetype of the buffer we initiated the action from.

Lets now take a look at the second prompt:

```lua
{
  role = "user",
  content = function(context)
    local text = require("codecompanion.helpers.actions").get_code(context.start_line, context.end_line)

    return "I have the following code:\n\n```" .. context.filetype .. "\n" .. text .. "\n```\n\n"
  end,
  opts = {
    contains_code = true,
  }
},
```

You can see that we're using a handy helper to get the code between two lines and formatting it into a markdown code block.

> [!IMPORTANT]
> We've also specified a `contains_code = true` flag. If you've turned off the sending of code to LLMs then the plugin will block this from happening.

### Conditionals

It's also possible to conditionally set prompts via a `condition` function that returns a boolean:

```lua
{
  role = "user",
  ---
  condition = function(context)
    return context.is_visual
  end,
  ---
},
```

And to determine the visibility of actions in the palette itself:

```lua
{
  name = "Open chats ...",
  strategy = " ",
  description = "Your currently open chats",
  condition = function()
    return #require("codecompanion").buf_get_chat() > 0
  end,
  picker = {
    ---
  }
}
```

## Other Configuration Options

### Allowing a Prompt to appear as a Slash Command

It can be useful to have a prompt from the prompt library appear as a slash command in the chat buffer, like with the `Generate a Commit Message` action. This can be done by specifying a `is_slash_cmd = true` option to the prompt:

```lua
["Generate a Commit Message"] = {
  strategy = "chat",
  description = "Generate a commit message",
  opts = {
    index = 9,
    is_default = true,
    is_slash_cmd = true,
    short_name = "commit",
    auto_submit = true,
  },
  prompts = {
    -- Prompts go here
  }
}
```

In the chat buffer, if you type `/` you will see the value of `opts.short_name` appear in the completion menu for you to expand.

### Specifying an Adapter and Model

```lua
["Your_New_Prompt"] = {
  strategy = "chat",
  description = "Your Special Prompt",
  opts = {
    adapter = {
      name = "ollama",
      model = "deepseek-coder:6.7b",
    },
  },
  -- Your prompts here
}
```

### Specifying a Placement for Inline Prompts

As outlined in the README, an inline prompt can place its response in many different ways. To override this, you can specify a specific placement:

```lua
["Your_New_Prompt"] = {
  strategy = "inline",
  description = "Your Special Inline Prompt",
  opts = {
    placement = "new"
  },
  -- Your prompts here
}
```

In this example, the LLM response will be placed in a new buffer and the user's code will not be returned back to them.

### Ignoring the default system prompt

It may also be useful to create custom prompts that do not send the default system prompt with the request:

```lua
["Your_New_Prompt"] = {
  strategy = "chat",
  description = "Your Special New Prompt",
  opts = {
    ignore_system_prompt = true,
  },
  -- Your prompts here
}
```

### Prompts with References

It can be useful to pre-load a chat buffer with references to _files_, _symbols_ or even _urls_. This makes conversing with an LLM that much more productive. As per `v11.9.0`, this can now be accomplished, as per the example below:

```lua
["Test References"] = {
  strategy = "chat",
  description = "Add some references",
  opts = {
    index = 11,
    is_default = true,
    is_slash_cmd = false,
    short_name = "ref",
    auto_submit = false,
  },
  -- These will appear at the top of the chat buffer
  references = {
    {
      type = "file",
      path = { -- This can be a string or a table of values
        "lua/codecompanion/health.lua",
        "lua/codecompanion/http.lua",
      },
    },
    {
      type = "file",
      path = "lua/codecompanion/schema.lua",
    },
    {
      type = "symbols",
      path = "lua/codecompanion/strategies/chat/init.lua",
    },
    {
      type = "url", -- This URL will even be cached for you!
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
},
```

## Agentic Workflows

Workflows, at their core, are simply multiple prompts which are sent to the LLM in a turn-based manner. I fully recommend reading [Issue 242](https://www.deeplearning.ai/the-batch/issue-242/) of The Batch to understand their use. Workflows are setup in exactly the same way as prompts in the prompt library. Take the `code workflow` as an example:

```lua
["Code workflow"] = {
  strategy = "workflow",
  description = "Use a workflow to guide an LLM in writing code",
  opts = {
    index = 4,
    is_default = true,
    short_name = "workflow",
  },
  prompts = {
    {
      -- We can group prompts together to make a workflow
      -- This is the first prompt in the workflow
      {
        role = constants.SYSTEM_ROLE,
        content = function(context)
          return fmt(
            "You carefully provide accurate, factual, thoughtful, nuanced answers, and are brilliant at reasoning. If you think there might not be a correct answer, you say so. Always spend a few sentences explaining background context, assumptions, and step-by-step thinking BEFORE you try to answer a question. Don't be verbose in your answers, but do provide details and examples where it might help the explanation. You are an expert software engineer for the %s language",
            context.filetype
          )
        end,
        opts = {
          visible = false,
        },
      },
      {
        role = constants.USER_ROLE,
        content = "I want you to ",
        opts = {
          auto_submit = false,
        },
      },
    },
    -- This is the second group of prompts
    {
      {
        role = constants.USER_ROLE,
        content = "Great. Now let's consider your code. I'd like you to check it carefully for correctness, style, and efficiency, and give constructive criticism for how to improve it.",
        opts = {
          auto_submit = false,
        },
      },
    },
    -- This is the final group of prompts
    {
      {
        role = constants.USER_ROLE,
        content = "Thanks. Now let's revise the code based on the feedback, without additional explanations.",
        opts = {
          auto_submit = false,
        },
      },
    },
  },
},
```

You'll notice that the comments use the notion of "groups". These are collections of prompts which are added to a chat buffer in a timely manner. Infact, the second group will only be added once the LLM has responded to the first group...and so on.

## Conclusion

Hopefully this serves as a useful introduction on how you can expand CodeCompanion to create prompts that suit your workflow. It's worth checking out [config.lua](https://github.com/olimorris/codecompanion.nvim/blob/main/lua/codecompanion/config.lua) files for more complex examples.

