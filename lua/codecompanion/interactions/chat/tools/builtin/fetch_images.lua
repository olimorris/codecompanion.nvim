local im_utils = require("codecompanion.utils.images")

---@class CodeCompanion.Tool.FetchImages: CodeCompanion.Tools.Tool
return {
  name = "fetch_images",
  cmds = {
    ---Execute the fetch_webpage tool
    ---@param tools CodeCompanion.Tools
    ---@param args {urls: string[]} The arguments from the LLM's tool call
    ---@param cb function Async callback for completion
    function(tools, args, _, cb)
      if args.urls == nil then
        return { status = "success" }
      end
      ---@type table<string, (CodeCompanion.Image|string)>
      local images = {}
      local has_image = false

      local processed_count = 0
      vim.iter(args.urls):each(
        ---@param url string
        function(url)
          im_utils.from_url(url, { chat_bufnr = tools.chat.bufnr, from = "tool" }, function(result)
            processed_count = processed_count + 1
            images[url] = result
            if type(result) == "table" then
              has_image = true
            end
            if processed_count == #args.urls then
              local status = "success"
              if not has_image and #args.urls > 0 then
                -- set status to error iff all images failed to load.
                status = "error"
              end
              cb({ status = status, data = images })
            end
          end)
        end
      )
    end,
  },
  schema = {
    type = "function",
    ["function"] = {
      name = "fetch_images",
      description = "Fetches images from the given URL(s).",
      parameters = {
        type = "object",
        properties = {
          urls = {
            type = "array",
            items = { type = "string" },
            description = "The URL of the images to fetch from. The URLs must come from the context or previous tool calls.",
          },
        },
        required = { "urls" },
      },
    },
  },
  output = {
    ---@param self CodeCompanion.Tool.FetchImages
    ---@param tools CodeCompanion.Tools
    ---@param cmd table The command that was executed
    ---@param stdout table The output from the command
    success = function(self, tools, cmd, stdout)
      local chat = tools.chat
      local total_count = #cmd.urls
      local failed_urls = {}

      ---@type table<string, (CodeCompanion.Image|string)>
      local results = stdout[#stdout]
      for url, item in pairs(results) do
        if type(item) == "table" then
          chat:add_image_message(
            item,
            { source = "codecompanion.strategies.chat.tools.fetch_images", add_context = false }
          )
        else
          failed_urls[#failed_urls + 1] = url
        end
      end

      if #failed_urls > 0 then
        chat:add_tool_output(
          self,
          "Failed to fetch images from the following URLs: " .. table.concat(failed_urls, ", "),
          string.format(
            "Successfully fetched %d images. Failed to fetch from %d URLs",
            total_count - #failed_urls,
            #failed_urls
          )
        )
      else
        chat:add_tool_output(self, string.format("Successfully fetched %d image(s).", total_count))
      end
    end,

    ---@param self CodeCompanion.Tool.FetchWebpage
    ---@param tools CodeCompanion.Tools
    ---@param cmd table The command that was executed
    ---@param stderr table The output from the command
    error = function(self, tools, cmd, stderr)
      tools.chat:add_tool_output(self, "Failed to fetch all images.")
    end,
  },
}
