---
name: writing-docs
description: Writing CodeCompanion.nvim docs. Use when creating or editing any page in `doc/`
---

# Writing Docs

Write CodeCompanion.nvim's docs following the Microsoft Writing Style Guide with the overrides below. Run `make docs` after changing any page to regenerate the vimdoc.

## Voice and Tone

- Write like you speak: friendly, direct and human, aimed at Neovim users. Avoid jargon where a familiar word works.
- Lead with what matters most. Front-load keywords so readers can scan.
- Say what happens, including the edge cases: "Optional arguments can be left blank, and cancelling at any point adds nothing".
- Be brief. Cut filler words, unnecessary adverbs and phrases like "you can", "there is" and "there are" where they add nothing. Prefer one-word verbs ("try", not "attempt to").
- Avoid marketing language and hedging: no "simply", "powerful", "awesome", "seamless" or "journey".
- Start with the content. Don't open with "This guide is intended to help you..." or close with "This is useful for...".

## Page Structure

- Frontmatter `description`: one sentence, what the page lets you do.
- The `#` title is "Using X" for usage pages, "Configuring X" for configuration pages and "Extending with X" for extending pages. Guides take a task title: "Running Local Models", "Choosing an Adapter".
- Open with one to three sentences: what the feature is, then how CodeCompanion does it. If the feature solves a problem, name the problem in a sentence first.
- `##` then `###` is the ceiling. For a sub-point under `###`, use a bold line (`**Images**`) instead of a deeper heading.
- Section names are short nouns or gerunds: "Directories", "Groups", "Autoload", "Editing and Deleting".
- End with a "Limitations" section when there are any, stated honestly.

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

- Lead-ins: "This can be configured with:", "You can override this with:", "To set an adapter:".
- Always wrap config examples in the full `require("codecompanion").setup({ ... })` nesting, so they can be pasted as-is.
- Use realistic values, not `foo` or `bar`.
- Inline comments list the allowed values or the unit, nothing more: `-- Can be "default", "telescope", "fzf_lua", "mini_pick" or "snacks"`, `-- milliseconds`.
- Use `::: code-group` for alternatives (Static and Conditional, Markdown and Lua) rather than two blocks with prose between them.
- Ex commands go in a bare fenced block with no language.
- Let the snippet speak for itself. Only add a sentence after it for behaviour the code can't show: "A directory further down the list takes precedence if skills of the same name clash".

## Lists and Tables

- More than two parallel things (commands, keymaps, events, feature support) go in a table.
- Three columns at most, as any more squashes the text on the site. If a column only differs for one or two rows, say so in a sentence after the table. If every row needs a sentence, use a bulleted list instead.
- Table descriptions are fragments with no trailing full stop: "Accept the current hunk, keeping it out of future reviews".
- Numbered lists for steps the user performs in order. Bulleted lists for options, with a bold name and a dash: `- **Chat** - A chat buffer where you can converse with an LLM`.

## Callouts

Use GitHub-style callouts, one or two sentences, with no trailing full stop:

```markdown
> [!NOTE]
> Only the text from a prompt's `user` messages is added. Images, resources and `assistant` messages are skipped
```

- `NOTE` for scope or restrictions, `IMPORTANT` for something that will bite, `TIP` for a shortcut, `WARNING` for something destructive or easy to get wrong.
- A callout that needs a paragraph is a section.

## Emphasis and Links

- Italics when introducing a term or naming a thing: the _baseline_, the _fetch_ slash command.
- Define a term where the reader first meets it on the page, even if another page explains it. That includes its first appearance as a config key, such as `interactions = {`.
- Bold for the one rule in a section the reader must not miss: "**Submitting the input empty deletes the comment**".
- Link to other doc pages with absolute paths and anchors: `[/skills](/usage/chat-buffer/slash-commands#skills)`. Link generously rather than repeating content from another page.

## Grammar

- Use present tense. Avoid "will" unless describing something that genuinely happens later.
- Use active voice wherever possible.
- Use second person ("you"). Use the imperative mood for procedures and setup steps, and plain statements of fact for everything else. Use suggestions and hypotheticals sparingly.
- Use common contractions (it's, you're, don't, that's).
- Don't use gendered pronouns for generic references. Use "you" or the person's role.
- Avoid chains of prepositional phrases and ambiguous modifiers. Place "only" next to the word it modifies.
- Don't give human characteristics to software: Neovim, the plugin, adapters and LLMs don't "think", "want" or "understand".

## Word Choice

- Use the same term for the same concept every time. Don't introduce synonyms for variety.
- Don't give common words new technical meanings, and don't invent terms where established ones exist.
- Avoid words with more than one meaning in context.

## Capitalisation and Punctuation

- Use title case for headings, matching the rest of the docs ("Adding Skills", "Editing and Deleting"). Use sentence-style capitalisation for list items.
- Don't end headings with a full stop or colon.
- End every sentence with a full stop, even short ones. Table descriptions and callouts are the exception.
- Leave out the comma before the final "and" or "or" in a list: "tables, callouts and code blocks".
- Use one space after full stops, question marks and colons.
- Use a colon to introduce a list. If list items are short phrases of three words or fewer, don't end them with full stops. If any item is a complete sentence, end every item with a full stop.
- Lowercase the word after a colon in a sentence unless it's a proper noun.
- Rewrite sentences that need semicolons as two sentences or a list.
- Use question marks and exclamation points sparingly.
- In prose, don't use a slash to mean "or". This doesn't apply to file paths, commands or code.
- Only hyphenate where leaving the hyphen out would cause confusion.
- Never use the em dash "—". Prefer restructuring the sentence with commas, parentheses or a full stop. If a dash is genuinely needed, use a spaced hyphen " - ".

## Numbers

- Spell out zero to nine. Use numerals for 10 and above.
- Use numerals for all numbers in a group if any one of them needs a numeral.
- Always use numerals for measurements, percentages (with "%"), time of day, version numbers and any value the reader types.
- Spell out a number that starts a sentence, or rewrite the sentence.
- Use ordinals as words ("first"), never "firstly".
- Use commas in numbers with four or more digits, except in years, code and config values.
- For dates, spell out the month and don't use ordinals ("10 October 2026", not "October 10th").
- Use "from... to" for ranges in prose.

## Technical Accuracy

- Write config keys, command names, function names, file paths, flags and plugin or adapter names exactly as they appear in the code, including case and punctuation: `strategy`, `:CodeCompanion`, `adapters.lua`.
- Use the vocabulary below as the spelling authority.
- Wrap code identifiers, config keys, commands and file paths in backticks.
- Style rules apply to prose only, never to code.
- Document only config options, commands, defaults, behaviour and version numbers that exist in the code. Check the source before stating any of them.

**Vocabulary:** CodeCompanion, CodeCompanion.nvim, Neovim, Lua, LuaCATS, Vim, VitePress, Tree-sitter, Mini.Test, StyLua, LLM, ACP, MCP, HTTP, Anthropic, Claude, Claude Code, OpenAI, Codex, Azure OpenAI, Copilot, Gemini, Gemini CLI, DeepSeek, Mistral, Mistral Vibe, xAI, Ollama, OpenRouter, Hugging Face, Novita, Kimi, Goose, Kiro, Cline, Cursor, OpenCode, Kilo Code, Auggie, Tavily, Jina, Serply, DuckDuckGo, MarkItDown, Telescope, fzf-lua, mini.pick, Snacks.

## Spelling

Use British English spelling: initialisation, customised, whilst.

## Before and After

Too much:

> The _fetch_ slash command allows you to add the contents of a URL to the chat buffer. By default, the plugin uses the awesome and powerful jina.ai to parse the page's content. This is really useful if you want to share documentation with your LLM. Simply type `/fetch` and follow the prompts.

Right:

> The _fetch_ slash command adds the contents of a URL to the chat buffer. By default, [jina.ai](https://jina.ai) converts the page into plain text.
