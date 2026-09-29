---
description: "Give the LLM in a CodeCompanion chat buffer access to web search, pick the search provider it uses, and fetch specific pages."
---

# Setting Up Web Search

An LLM only knows what it was trained on, so it can't tell you about a library released last week. The [web_search](/usage/chat-buffer/agents-tools#web-search) tool lets it search the web from the chat buffer, sending its query to a search provider through an adapter.

## Choosing a Search Provider

The default provider is Tavily, which needs an API key. If you haven't set one, every search fails.

| Adapter | API key | Notes |
|---|---|---|
| `tavily` | `TAVILY_API_KEY` | The default. Returns relevant chunks from each result |
| `serply` | `SERPLY_API_KEY` | Google results. Returns at most 10 per search |
| `duckduckgo` | None | Reads DuckDuckGo's HTML results page. Ignores every search option |

To pick one:

::: code-group

```lua [Tavily]
-- Reads the TAVILY_API_KEY environment variable
require("codecompanion").setup({
  interactions = {
    chat = {
      tools = {
        ["web_search"] = {
          opts = {
            adapter = "tavily",
          },
        },
      },
    },
  },
})
```

```lua [Serply]
-- Reads the SERPLY_API_KEY environment variable
require("codecompanion").setup({
  interactions = {
    chat = {
      tools = {
        ["web_search"] = {
          opts = {
            adapter = "serply",
          },
        },
      },
    },
  },
})
```

```lua [DuckDuckGo]
-- No API key required
require("codecompanion").setup({
  interactions = {
    chat = {
      tools = {
        ["web_search"] = {
          opts = {
            adapter = "duckduckgo",
          },
        },
      },
    },
  },
})
```

:::

> [!IMPORTANT]
> Don't put `strategies` and `interactions` in the same config. `strategies` is the old name, and when it's present your `interactions` table is replaced, so the tool falls back to Tavily

To read the API key from somewhere else, such as a password manager:

```lua
require("codecompanion").setup({
  adapters = {
    http = {
      extend = {
        tavily = {
          env = {
            api_key = "cmd:op read op://personal/Tavily/credential --no-newline",
          },
        },
      },
    },
  },
})
```

See [environment variables](/configuration/adapters-http#environment-variables) for the other ways to set a key.

## Searching

Add `@{web_search}` to your message:

```md
Use @{web_search} to find the latest release of Neovim and summarise what changed
```

The LLM writes the query itself and can limit it to particular sites:

```md
Use @{web_search} to search neovim.io and explain how I configure a new language server
```

The search runs without asking for your approval. The results go back to the LLM as a list of titles, URLs and snippets, not full pages. If it needs a whole page, give it [fetch_webpage](#fetching-a-page) too.

> [!NOTE]
> DuckDuckGo ignores the list of sites, so the search covers the whole web

### Search Options

The tool passes the options in `opts.opts` to the adapter. The defaults are:

```lua
require("codecompanion").setup({
  interactions = {
    chat = {
      tools = {
        ["web_search"] = {
          opts = {
            adapter = "tavily",
            opts = {
              search_depth = "advanced", -- Can be "basic" or "advanced"
              topic = "general", -- Can be "general" or "news"
              chunks_per_source = 3,
              max_results = 5,
            },
          },
        },
      },
    },
  },
})
```

| Option | Adapter | Description |
|---|---|---|
| `max_results` | Tavily, Serply | Number of results to return |
| `topic` | Tavily, Serply | `"news"` searches news only |
| `time_range` | Tavily, Serply | Only return results from the last `"day"`, `"week"`, `"month"` or `"year"` |
| `search_depth` | Tavily | `"advanced"` returns more relevant chunks, at a higher cost per search |
| `chunks_per_source` | Tavily | Number of chunks taken from each result |
| `days` | Tavily | How far back a `"news"` search goes (default `7`) |
| `gl` | Serply | Country to search from, such as `"gb"` |
| `hl` | Serply | Interface language, such as `"en"` |

## Provider Web Search

Some providers run web search on their own servers. With these adapters, `@{web_search}` uses the provider's search instead of the tool above, so your search adapter and its API key aren't used:

| Adapter | Provider tools |
|---|---|
| `anthropic` | `web_search`, and `web_fetch` for fetching a page |
| `openai_responses` | `web_search` |
| `gemini_interactions` | `web_search`, using Google Search |
| `openrouter` | `web_search`, and `fetch_webpage` in place of the [built-in tool](#fetching-a-page) |

Anything the provider charges for search is added to your bill with them. To use the built-in tool instead, turn the provider's tool off:

```lua
require("codecompanion").setup({
  adapters = {
    http = {
      extend = {
        anthropic = {
          available_tools = {
            ["web_search"] = {
              enabled = false,
            },
          },
        },
      },
    },
  },
})
```

See [adapter tools](/usage/chat-buffer/agents-tools#adapter-tools) for more.

## Fetching a Page

When you already know the page you want, you don't need a search. There are two ways to add a page to the chat:

- **`@{fetch_webpage}`** - A tool. The LLM decides which URL to fetch and reads the result straight away
- **`/fetch`** - A [slash command](/usage/chat-buffer/slash-commands#fetch). You enter the URL, and can cache the page to add it again later without fetching it

```md
Use @{fetch_webpage} to read https://neovim.io/doc/user/lsp.html and tell me how to disable semantic tokens
```

Both use [Jina](https://jina.ai) by default, which works without an API key and converts the page into plain text. [MarkItDown](https://github.com/microsoft/markitdown) is the alternative. It runs the `markitdown` CLI on your machine, so it must be installed. Each one has its own adapter setting:

```lua
require("codecompanion").setup({
  interactions = {
    chat = {
      tools = {
        ["fetch_webpage"] = {
          opts = {
            adapter = "markitdown", -- Can be "jina" or "markitdown"
          },
        },
      },
      slash_commands = {
        ["fetch"] = {
          opts = {
            adapter = "markitdown", -- Can be "jina" or "markitdown"
          },
        },
      },
    },
  },
})
```

To send a Jina API key with each request:

```lua
require("codecompanion").setup({
  adapters = {
    http = {
      extend = {
        jina = {
          env = {
            api_key = "JINA_API_KEY",
          },
        },
      },
    },
  },
})
```

## Limitations

- The tools are for HTTP adapters only. Agents like Claude Code bring their own web search
- The model you use must support tool use. Smaller local models may not call the tool, or may call it with a malformed query
- Only one search adapter can be set at a time, and it's shared by every chat
- DuckDuckGo reads a web page meant for people, so it can refuse the request and return "Engine thinks you're a bot", or stop working if the page changes
- Search results are snippets. The LLM needs `@{fetch_webpage}` as well to read a result in full
