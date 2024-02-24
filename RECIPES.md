# Recipes

The purpose of this guide is to showcase how you can extend the functionality of CodeCompanion by adding your own actions to the _Action Palette_.

The _Action Palette_ is a lua table which is parsed by the plugin and displayed as a `vim.ui.select` component. By specifying certain keys, the behaviour of the table can be customised further.

## Adding an action to the palette

Actions can be added via the `setup` function:

```lua
require("codecompanion").setup({
  actions = {
    {
      name = "My new action",
      strategy = "chat",
      description = "Some cool action you can do",
      prompts = {
        {
          role = "system",
          content = "you can do something cool",
        },
      },
    }
  }
})
```

In this example, if you run `:CodeCompanionActions`, you should see "My new action" at the bottom of the palette. Clicking on it will initiate the _chat_ strategy and set the value of the chat buffer based on the _role_ and _content_ that's been specified in the prompt.

In the following sections, we'll explore how you can customise these actions even more.

## Recipe #1: Creating boilerplate code

### Boilerplate HTML

As the years go by, I find myself writing less and less HTML. So when it comes to quickly scaffolding out a HTML page, I inevitably turn to a search engine. It would be great if I could have an action that could quickly generate some boilerplate HTML from the _Action Palette_.

Let's take a look at how we can achieve that below:

```lua
require("codecompanion").setup({
  actions = {
    {
      name = "Boilerplate HTML",
      strategy = "inline",
      description = "Generate some boilerplate HTML",
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

Nice! We've used some careful prompting to ensure that we get the HTML boilerplate. But we could expand this far beyond just HTML.

### MORE boilerplate

With the _Action Palette_ we can call additional `vim.ui.select` components with the `picker` table key. Let's expand on our HTML boilerplate by adding some Ruby on Rails controller boilerplate:

```lua
require("codecompanion").setup({
  actions = {
    {
      name = "Boilerplate",
      strategy = "inline",
      description = "Generate some boilerplate",
      picker = {
        prompt = "Select some boilerplate",
        items = {
          {
            name = "HTML boilerplate",
            strategy = "inline",
            description = "Create some HTML boilerplate",
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
          {
            name = "Rails Controller",
            strategy = "inline",
            description = "Create some Rails controller boilerplate",
            prompts = {
              {
                role = "system",
                content = "You are an expert Ruby on Rails programmer",
              },
              {
                role = "user",
                content = "Please generate a Rails controller. Return the code only and no markdown codeblocks",
              },
            },
          },
        },
      },
    },
  }
})
```

If you run `:CodeCompanionActions`, you should see that the two boilerplate prompts are now nested in their own `vim.ui.select` component.

### Leveraging pre-hooks

To make this example complete, we can leverage a pre-hook to create a new buffer and set the filetype to be html:

```lua
{
  name = "HTML boilerplate",
  strategy = "inline",
  description = "Create some HTML boilerplate",
  pre_hook = function()
    local bufnr = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_option(bufnr, "filetype", "html")
    vim.api.nvim_set_current_buf(bufnr)
    return bufnr
  end
}
```

For the inline strategy, the plugin will detect a number being returned and assume that is the buffer number you wish any code to be streamed into.

### Conclusion

Whilst these examples were useful at demonstrating the functionality of the _Action Palette_, they're not making the most of the GenAI models to add any real value to your workflow (this boilerplate could be snippets after all). So let's step things up in the next section.

## Recipe #2: Using context in your prompts

Now let's look at how we can get GenAI to advise us on some selected code. This is builtin to the plugin as the _Code advisor_ action:

```lua
require("codecompanion").setup({
  actions = {
    {
      name = "Special advisor",
      strategy = "chat",
      description = "Get some special GenAI advice",
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
            local text = require("codecompanion.helpers.code").get_code(context.start_line, context.end_line)

            return "I have the following code:\n\n```" .. context.filetype .. "\n" .. text .. "\n```\n\n"
          end,
        },
      },
    },
  },
})
```

Holy smokes there's a lot of new stuff in this. Let's break it down.

### Palette options

```lua
opts = {
  modes = { "v" },
  auto_submit = true,
  user_prompt = true,
},
```

In the `opts` table we're specifying that we only want this action to appear if we're in visual mode. We're also asking the chat strategy to automatically send the prompts to OpenAI. It may be useful to turn this off if you wish to add some additional context prior to asking for a response. Finally, we're telling the picker that we want to prompt the user for some custom input.

### Prompt options and context

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
    contains_code = true,
    content = function(context)
      local text = require("codecompanion.helpers.code").get_code(context.start_line, context.end_line)

      return "I have the following code:\n\n```" .. context.filetype .. "\n" .. text .. "\n```\n\n"
    end,
  },
},
```

One of the most useful features of the _Action Palette_ prompts is the ability to receive context about the current buffer which can then be used in the prompts themselves. A typical context table looks like:

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
  winid = 1000
}
```

Using the above context as an example, our first prompt then makes more sense:

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

We are telling the GenAI model to act as a "senior _Lua_ developer" based on the filetype of the buffer we initiated the action from.

Lets now take a look at the second prompt:

```lua
{
  role = "user",
  contains_code = true,
  content = function(context)
    local text = require("codecompanion.helpers.code").get_code(context.start_line, context.end_line)

    return "I have the following code:\n\n```" .. context.filetype .. "\n" .. text .. "\n```\n\n"
  end,
},
```

You can see that we're using a handy helper to get the code between two lines and formatting it into a markdown code block.

> [!IMPORTANT]
> We've also specifed a `contains_code = true` flag. If you've turned off the sending of code to a GenAI model then the
> plugin will block this from happening.

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
  name = "Load saved chats ...",
  strategy = "saved_chats",
  description = "Load your previously saved chats",
  condition = function()
    local saved_chats = require("codecompanion.strategy.saved_chats")
    return saved_chats:has_chats()
  end,
  picker = {
    ---
  }
}
```

## Conclusion

Hopefully this serves as a useful introduction on how you can expand CodeCompanion to create custom actions that suit your workflow. It's worth checking out the [actions.lua](https://github.com/olimorris/codecompanion.nvim/blob/5cac252cc402429ac766f1b1fe54988d89391206/lua/codecompanion/actions.lua) for more complex examples.
