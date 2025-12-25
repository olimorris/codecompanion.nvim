local adapters = require("codecompanion.adapters")
local client = require("codecompanion.http")
local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")

local fmt = string.format

---@class CodeCompanion.Tool.FetchWebpage: CodeCompanion.Tools.Tool
return {
  name = "fetch_webpage",
  cmds = {
    ---Execute the fetch_webpage tool
    ---@param self CodeCompanion.Tools
    ---@param args table The arguments from the LLM's tool call
    ---@param cb function Async callback for completion
    ---@return nil
    function(self, args, _, cb)
      local opts = self.tool.opts
      local url = args.url
      args.content_format = args.content_format or "text"

      if not opts or not opts.adapter then
        log:error("[Fetch Webpage Tool] No adapter set for `fetch_webpage`")
        return cb({ status = "error", data = "No adapter for `fetch_webpage`" })
      end
      if not args then
        log:error("[Fetch Webpage Tool] No args for `fetch_webpage`")
        return cb({ status = "error", data = "No args for `fetch_webpage`" })
      end

      if not url or type(url) ~= "string" or url == "" then
        return cb({ status = "error", data = fmt("No URL for `fetch_webpage`") })
      end

      local tool_adapter = config.interactions.chat.tools.fetch_webpage.opts.adapter
      local adapter = vim.deepcopy(adapters.resolve(tool_adapter))
      adapter.methods.tools.fetch_webpage.setup(adapter, args)

      if args.content_format ~= "text" then
        if type(self.chat.adapter.opts) == "table" and not self.chat.adapter.opts.vision then
          log:warn("[Fetcg Webpage Tool] Setting `content_format` to text because the chat adapter disabled vision.")
          args.content_format = "text"
        end
      end

      if not url:match("^https?://") then
        log:error("[Fetch Webpage Tool] Invalid URL: `%s`", url)
        return cb({ status = "error", data = fmt("Invalid URL: `%s`", url) })
      end

      client
        .new({
          adapter = adapter,
        })
        :request({ messages = {}, tools = nil }, {
          callback = function(err, data)
            if err then
              log:error("[Fetch Webpage Tool] Error fetching `%s`: %s", url, err)
              return cb({ status = "error", data = fmt("Error fetching `%s`\n%s", url, err) })
            end

            if data then
              local output = adapter.methods.tools.fetch_webpage.callback(adapter, data)
              if output.status == "error" then
                log:error("[Fetch Webpage Tool] Error processing data for `%s`: %s", url, output.content)
                return cb({ status = "error", data = fmt("Error processing `%s`\n%s", url, output.content) })
              end

              return cb({
                status = "success",
                data = {
                  text = (args.content_format == "text") and output.content.text or nil,
                  screenshot = (args.content_format == "screenshot") and output.content.screenshot or nil,
                  pageshot = (args.content_format == "pageshot") and output.content.pageshot or nil,
                },
              })
            end
          end,
        })
    end,
  },
  schema = {
    type = "function",
    ["function"] = {
      name = "fetch_webpage",
      description = "Fetches the main content from a web page. You should use this tool when you think the user is looking for information from a specific webpage.",
      parameters = {
        type = "object",
        properties = {
          url = {
            type = "string",
            description = "The URL of the webpage to fetch content from",
          },
          content_format = {
            type = "string",
            enum = { "text", "screenshot", "pageshot" },
            description = [[How the result should be presented.
- `text`: Returns `document.body.innerText`.
- `screenshot`: Returns the image URL of a screenshot of the first screen.
- `pageshot`: Returns the image URL of the full-page screenshot.
Choose `screenshot` or `pageshot` if you need to know the layout, design or image information of the website AND you have vision capability.
Otherwise, stick to `text`.
When you receive a URL to the screenshot or pageshot, you should call the `fetch_images` tool to see the image.
        ]],
          },
        },
        required = { "url", "content_format" },
      },
    },
  },
  output = {
    ---@param self CodeCompanion.Tool.FetchWebpage
    ---@param tools CodeCompanion.Tools
    ---@param cmd table The command that was executed
    ---@param stdout table The output from the command
    success = function(self, tools, cmd, stdout)
      local args = self.args
      local chat = tools.chat

      local llm_output
      local user_output
      local output = stdout[#stdout]
      if type(output.text) == "string" then
        llm_output = fmt([[<attachment url="%s">%s</attachment>]], args.url, output.text)
        user_output = fmt("Fetched content from `%s`", args.url)
      elseif type(output.screenshot) == "string" then
        llm_output = fmt([[<attachment image_url="%s">Screenshot of %s</attachment>]], output.screenshot, args.url)
        user_output = fmt("Fetched screenshot of `%s`", args.url)
      elseif type(output.pageshot) == "string" then
        llm_output = fmt([[<attachment image_url="%s">Pageshot of %s</attachment>]], output.pageshot, args.url)
        user_output = fmt("Fetched pageshot of `%s`", args.url)
      end

      chat:add_tool_output(self, llm_output, user_output)
    end,

    ---@param self CodeCompanion.Tool.FetchWebpage
    ---@param tools CodeCompanion.Tools
    ---@param cmd table
    ---@param stderr table The error output from the command
    error = function(self, tools, cmd, stderr)
      local args = self.args
      local chat = tools.chat
      local errors = vim.iter(stderr):flatten():join("\n")
      log:debug("[Fetch Webpage Tool] Error output: %s", stderr)

      local error_output = fmt(
        [[Error fetching content from `%s`:
```txt
%s
```]],
        args.url,
        errors
      )
      chat:add_tool_output(self, error_output)
    end,
  },
}
