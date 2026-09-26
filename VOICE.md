# Docs Voice

How the CodeCompanion docs are written. Follow this when writing or editing anything in `doc/`.

## Tone

- Plain, direct, second person ("you"). Contractions are fine
- British spelling: initialisation, customised, whilst
- Say what happens, including the edge cases: "Optional arguments can be left blank, and cancelling at any point adds nothing"
- No marketing. No "simply", "powerful", "awesome", "seamless", "journey"
- No throat-clearing. Don't open with "This guide is intended to help you..." or close with "This is useful for..."
- Never use an em dash. Use a plain dash

## Page Structure

- Frontmatter `description`: one sentence, what the page lets you do
- `#` title is "Using X" for usage pages and "Configuring X" for configuration pages
- Open with one to three sentences: what the feature is, then how CodeCompanion does it. If the feature solves a problem, name the problem in a sentence first
- `##` then `###` is the ceiling. Never `####`. For a sub-point under `###`, use a bold line (`**Images**`) instead
- Section names are short nouns or gerunds: "Directories", "Groups", "Autoload", "Editing and Deleting"
- End with a "Limitations" section when there are any, stated honestly

## Code First

The rhythm is a one-line lead-in ending in a colon, then the code block:

````markdown
Skills are enabled by default. To disable them:

```lua
require("codecompanion").setup({
  skills = {
    opts = {
      chat = {
        enabled = false,
      },
    },
  },
})
```
````

- Lead-ins: "This can be configured with:", "You can override this with:", "To set an adapter:"
- Always wrap config examples in the full `require("codecompanion").setup({ ... })` nesting, so they can be pasted as-is
- Use realistic values, not `foo`/`bar`
- Inline comments list the allowed values or the unit, nothing more: `-- Can be "default", "telescope", "fzf_lua", "mini_pick" or "snacks"`, `-- milliseconds`
- Use `::: code-group` for alternatives (Static/Conditional, Markdown/Lua) rather than two blocks with prose between them
- Ex commands go in a bare fenced block with no language
- Don't follow a snippet with a paragraph restating what it does. Only add a sentence after it if there's behaviour the code can't show ("A directory further down the list takes precedence if skills of the same name clash")

## Lists and Tables

- More than two parallel things (commands, keymaps, events, feature support) go in a table
- Table descriptions are fragments with no trailing full stop: "Accept the current hunk, keeping it out of future reviews"
- Numbered lists for steps the user performs in order. Bulleted lists for options, with a bold name and a dash: `- **Chat** - A chat buffer where you can converse with an LLM`

## Callouts

Use GitHub-style callouts, one or two sentences, often with no full stop:

```markdown
> [!NOTE]
> Only the text from a prompt's `user` messages is added. Images, resources and `assistant` messages are skipped
```

- `NOTE` for scope or restrictions, `IMPORTANT` for something that will bite, `TIP` for a shortcut, `WARNING` for something destructive or easy to get wrong
- A callout is not a place for a paragraph. If it needs one, it's a section

## Emphasis and Links

- Italics when introducing a term or naming a thing: the _baseline_, the _fetch_ slash command
- Bold for the one rule in a section the reader must not miss: "**Submitting the input empty deletes the comment**"
- Link to other doc pages with absolute paths and anchors: `[/skills](/usage/chat-buffer/slash-commands#skills)`. Link generously rather than repeating content from another page

## Before and After

Too much:

> The _fetch_ slash command allows you to add the contents of a URL to the chat buffer. By default, the plugin uses the awesome and powerful jina.ai to parse the page's content. This is really useful if you want to share documentation with your LLM. Simply type `/fetch` and follow the prompts.

Right:

> The _fetch_ slash command adds the contents of a URL to the chat buffer. By default, [jina.ai](https://jina.ai) converts the page into plain text.
