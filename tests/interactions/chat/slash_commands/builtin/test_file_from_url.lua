local new_set = MiniTest.new_set
local h = require("tests.helpers")

local child = MiniTest.new_child_neovim()

local T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        h = require("tests.helpers")
        _G.chat = h.setup_chat_buffer()
        _G.chat.adapter.opts = vim.tbl_extend("force", _G.chat.adapter.opts or {}, { vision = true })
      ]])
    end,
    post_once = child.stop,
  },
})

---Serve a stub file from `Curl.get` instead of the network, then run the slash command
---@param opts { url: string, file?: string, content_type?: string, status?: number }
---@return table|nil The last message in the chat
local function download(opts)
  return child.lua(
    [[
    local opts = ...
    require("plenary.curl").get = function(_, request)
      if opts.file then
        vim.uv.fs_copyfile(opts.file, request.output)
      end
      request.callback({ status = opts.status or 200, headers = { "Content-Type: " .. (opts.content_type or "") } })
    end

    local before = #_G.chat.messages
    require("codecompanion.interactions.chat.slash_commands.builtin.file_from_url")
      .new({ Chat = _G.chat, config = { opts = {} } })
      :output(opts.url)

    vim.wait(1000, function() return #_G.chat.messages > before end, 10)
    if #_G.chat.messages == before then
      return nil
    end
    return _G.chat.messages[#_G.chat.messages]
  ]],
    { opts }
  )
end

T["File from URL"] = new_set()

T["File from URL"]["adds an image as an image message, labelled with its URL"] = function()
  local message = download({
    url = "https://example.com/logo.png",
    file = "tests/stubs/logo.png",
    content_type = "image/png",
  })

  h.eq("image", message._meta.tag)
  h.eq("image/png", message.context.mimetype)
  h.eq("<image>https://example.com/logo.png</image>", message.context.id)
end

T["File from URL"]["adds a text file as file content, labelled with its URL"] = function()
  local message = download({
    url = "https://example.com/stub.lua",
    file = "tests/stubs/stub.lua",
    content_type = "text/plain; charset=utf-8",
  })

  h.eq("file", message._meta.tag)
  h.eq("<file>https://example.com/stub.lua</file>", message.context.id)
  h.expect_contains('<attachment filepath="https://example.com/stub.lua">', message.content)
  h.expect_contains("```lua", message.content)
end

T["File from URL"]["hands a webpage to the fetch slash command"] = function()
  local fetched = child.lua([[
    local fetched
    package.loaded["codecompanion.interactions.chat.slash_commands.builtin.fetch"] = {
      new = function()
        return { output = function(_, url) fetched = url end }
      end,
    }
    require("plenary.curl").get = function(_, request)
      request.callback({ status = 200, headers = { "content-type: text/html; charset=utf-8" } })
    end

    require("codecompanion.interactions.chat.slash_commands.builtin.file_from_url")
      .new({ Chat = _G.chat, config = { opts = {} } })
      :output("https://example.com")

    vim.wait(1000, function() return fetched ~= nil end, 10)
    return fetched
  ]])

  h.eq("https://example.com", fetched)
end

T["File from URL"]["DOES NOT add anything when the download fails"] = function()
  h.eq(vim.NIL, download({ url = "https://example.com/missing.png", status = 404 }))
end

return T
