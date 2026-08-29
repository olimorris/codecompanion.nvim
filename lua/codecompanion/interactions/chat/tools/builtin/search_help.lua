local tool_helpers = require("codecompanion.interactions.chat.tools.builtin.helpers")

local file_utils = require("codecompanion.utils.files")
local log = require("codecompanion.utils.log")

local fmt = string.format

local CONSTANTS = {
  DOC_NAME = "codecompanion.txt",
  PATH_SEPARATOR = " > ",
}

local cached_doc = nil

---@return string?
local function get_help_docs()
  local source = debug.getinfo(1, "S").source
  if source:sub(1, 1) == "@" then
    for dir in vim.fs.parents(vim.fs.normalize(source:sub(2))) do
      local candidate = vim.fs.joinpath(dir, "doc", CONSTANTS.DOC_NAME)
      if file_utils.exists(candidate) then
        return candidate
      end
    end
  end

  local from_runtime = vim.api.nvim_get_runtime_file("doc/" .. CONSTANTS.DOC_NAME, false)
  return from_runtime[1]
end

---@param line string
---@param context { follows_rule: boolean, follows_blank: boolean }
---@return { level: number, title: string, tag: string? }?
local function classify_heading(line, context)
  local before_tag, tag = line:match("^(.-)%s*%*([%w%-%.%(%)]+)%*%s*$")
  if tag then
    local title = vim.trim(before_tag)
    if title == "" then
      return nil
    end
    if context.follows_rule and title:match("^%d+%.%s") then
      return { level = 1, title = title:gsub("^%d+%.%s*", ""), tag = tag }
    end
    if title:match("^[%u%d][%u%d%s/%(%)%-'&,%.]*$") then
      return { level = 2, title = title, tag = tag }
    end
    return nil
  end

  -- Lowercase is the tell, not a leading capital, or the `/slash_command` and `#editor_context` headings are missed
  local subheading = line:match("^(%S.-)%s~$")
  if subheading and not subheading:match("%l") then
    return { level = 3, title = vim.trim(subheading) }
  end

  -- Only the blank line stops prose that wrapped onto an all-caps fragment (`URL.`) reading as a heading
  if
    context.follows_blank
    and not line:match("%.$")
    and not line:match("%l")
    and line:match("^[%u%d/#@][%u%d%s/%(%)%-'&,%.:_#@]*$")
    and line:match("%a")
    and #vim.trim(line) > 1
  then
    return { level = 4, title = vim.trim(line) }
  end

  return nil
end

---@param lines string[]
---@return table[]
local function scan_headings(lines)
  local nodes = {}
  local in_code_block = false
  local follows_rule = false
  local follows_blank = false

  for number, line in ipairs(lines) do
    -- The preceding space is required, otherwise an inline URL like <https://x.com> opens a code block
    if not in_code_block and (line:match("^>%a*$") or line:match("%s>%a*$")) then
      in_code_block = true
    elseif in_code_block and line:match("^<") then
      in_code_block = false
    elseif not in_code_block then
      local heading = classify_heading(line, { follows_rule = follows_rule, follows_blank = follows_blank })
      if heading then
        heading.line = number
        table.insert(nodes, heading)
      end
    end
    follows_rule = line:match("^=+$") ~= nil
    follows_blank = vim.trim(line) == ""
  end

  return nodes
end

---Record the line ranges each heading owns and the breadcrumb that addresses it
---@param nodes table[]
---@param total_lines number
---@return nil
local function annotate_headings(nodes, total_lines)
  for index, node in ipairs(nodes) do
    node.index = index
    node.content_end = nodes[index + 1] and (nodes[index + 1].line - 1) or total_lines

    node.subtree_end = total_lines
    for later = index + 1, #nodes do
      if nodes[later].level <= node.level then
        node.subtree_end = nodes[later].line - 1
        break
      end
    end

    local trail = { node.title }
    local shallowest = node.level
    for ancestor = index - 1, 1, -1 do
      if shallowest == 1 then
        break
      end
      if nodes[ancestor].level < shallowest then
        table.insert(trail, 1, nodes[ancestor].title)
        shallowest = nodes[ancestor].level
      end
    end
    node.path = table.concat(trail, CONSTANTS.PATH_SEPARATOR)
  end
end

---@param lines string[]
---@return table[]
local function build_outline(lines)
  local nodes = scan_headings(lines)
  annotate_headings(nodes, #lines)
  return nodes
end

---@return { lines: string[], nodes: table[], path: string }?
---@return string? error_msg
local function load_doc()
  if cached_doc then
    return cached_doc
  end

  local path = get_help_docs()
  if not path then
    return nil, "Could not locate CodeCompanion's help file"
  end

  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok or type(lines) ~= "table" then
    return nil, fmt("Could not read `%s`", path)
  end

  cached_doc = { lines = lines, nodes = build_outline(lines), path = path }
  return cached_doc
end

---Normalize a tag or heading path so matching ignores case and spacing
---@param needle string
---@return string
local function normalize(needle)
  return vim.trim(needle:lower():gsub("%s*>%s*", " > "):gsub("%s+", " "))
end

---Find sections matching a tag or heading path, returning only the best tier of matches
---@param nodes table[]
---@param needle string
---@return table[]
local function find_sections(nodes, needle)
  local wanted = normalize(needle)
  if wanted == "" then
    return {}
  end

  local exact, suffix, partial = {}, {}, {}
  for _, node in ipairs(nodes) do
    local path = normalize(node.path)
    if (node.tag and node.tag:lower() == wanted) or path == wanted or normalize(node.title) == wanted then
      table.insert(exact, node)
    elseif vim.endswith(path, " > " .. wanted) then
      table.insert(suffix, node)
    elseif path:find(wanted, 1, true) then
      table.insert(partial, node)
    end
  end

  if next(exact) then
    return exact
  end
  return next(suffix) and suffix or partial
end

---Drop the blank lines and chapter rule that bleed in from whatever follows a section
---@param lines string[]
---@param range { first: number, last: number }
---@return number
local function trim_trailing(lines, range)
  local last = range.last
  while last > range.first and (vim.trim(lines[last]) == "" or lines[last]:match("^=+$")) do
    last = last - 1
  end
  return last
end

---@param nodes table[]
---@param node table
---@return table[]
local function direct_children(nodes, node)
  local children = {}
  local child_level
  for index = node.index + 1, #nodes do
    local candidate = nodes[index]
    if candidate.line > node.subtree_end then
      break
    end
    child_level = child_level or candidate.level
    if candidate.level == child_level then
      table.insert(children, candidate)
    end
  end
  return children
end

---@param node table
---@param opts? { indent: boolean }
---@return string
local function render_heading(node, opts)
  local indent = (opts and opts.indent) and string.rep("  ", node.level - 1) or ""
  return fmt("%s%s%s", indent, node.title, node.tag and fmt("  |%s|", node.tag) or "")
end

---Build the navigable outline of the whole doc or one section
---@param doc table
---@param args { section?: string, max_level?: number }
---@return {status: "success"|"error", data: string}
local function run_outline(doc, args)
  local scope = doc.nodes
  local header = fmt("Outline of CodeCompanion's help (%d sections)", #doc.nodes)

  if args.section and args.section ~= "" then
    local matches = find_sections(doc.nodes, args.section)
    if not next(matches) then
      return {
        status = "error",
        data = fmt("No section matches `%s`. Run `outline` with no section to see them all.", args.section),
      }
    end
    local node = matches[1]
    scope = vim.tbl_filter(function(candidate)
      return candidate.line >= node.line and candidate.line <= node.subtree_end
    end, doc.nodes)
    header = fmt("Outline of `%s`", node.path)
  end

  local max_level = args.max_level or (args.section and 4 or 2)
  local rendered = vim
    .iter(scope)
    :filter(function(node)
      return node.level <= max_level
    end)
    :map(function(node)
      return render_heading(node, { indent = true })
    end)
    :totable()

  return { status = "success", data = fmt("%s\n\n%s", header, table.concat(rendered, "\n")) }
end

---Render a section and everything nested under it
---@param doc table
---@param node table
---@return {status: "success", data: string}
local function render_section(doc, node)
  local last = trim_trailing(doc.lines, { first = node.line, last = node.subtree_end })
  local body = table.concat(vim.list_slice(doc.lines, node.line, last), "\n")
  return {
    status = "success",
    data = fmt("`%s` (lines %d-%d of %s)\n````vimdoc\n%s\n````", node.path, node.line, last, CONSTANTS.DOC_NAME, body),
  }
end

---Render a section's introduction and the subsections to read instead of the whole thing
---@param doc table
---@param node table
---@return {status: "success", data: string}
local function render_section_summary(doc, node)
  local intro_last = trim_trailing(doc.lines, { first = node.line, last = node.content_end })
  local intro = table.concat(vim.list_slice(doc.lines, node.line, intro_last), "\n")
  local children = vim.tbl_map(function(child)
    return fmt("  %s  (%d lines)", child.path, child.subtree_end - child.line + 1)
  end, direct_children(doc.nodes, node))

  return {
    status = "success",
    data = fmt(
      "`%s` spans %d lines, so only its introduction is shown. Read one of its subsections for the rest.\n````vimdoc\n%s\n````\nSubsections:\n%s",
      node.path,
      node.subtree_end - node.line + 1,
      intro,
      table.concat(children, "\n")
    ),
  }
end

---Read a section, falling back to its child outline when it is too long to return whole
---@param doc table
---@param args { section: string }
---@param max_lines number
---@return {status: "success"|"error", data: string}
local function run_read(doc, args, max_lines)
  if not args.section or args.section == "" then
    return { status = "error", data = "The `read` command requires a `section` parameter" }
  end

  local matches = find_sections(doc.nodes, args.section)
  if not next(matches) then
    return {
      status = "error",
      data = fmt("No section matches `%s`. Use the `search` or `outline` command to find one.", args.section),
    }
  end

  if #matches > 1 then
    local candidates = vim.tbl_map(function(node)
      return "  " .. node.path
    end, matches)
    return {
      status = "error",
      data = fmt(
        "`%s` matches %d sections. Read one of these instead:\n%s",
        args.section,
        #matches,
        table.concat(candidates, "\n")
      ),
    }
  end

  local node = matches[1]
  if (node.subtree_end - node.line + 1) <= max_lines then
    return render_section(doc, node)
  end
  return render_section_summary(doc, node)
end

---Build the line matcher for a search, literal by default and a Lua pattern on request
---@param args { query: string, regex?: boolean }
---@return fun(line: string): boolean? matcher
---@return string? error_msg
local function build_matcher(args)
  if args.regex then
    local valid = pcall(string.find, "", args.query)
    if not valid then
      return nil, fmt("`%s` is not a valid Lua pattern", args.query)
    end
    return function(line)
      return line:find(args.query) ~= nil
    end
  end

  local needle = args.query:lower()
  return function(line)
    return line:lower():find(needle, 1, true) ~= nil
  end
end

---Walk the doc collecting matching lines against the section each one sits in
---@param doc table
---@param matches_line fun(line: string): boolean
---@param max_results number
---@return { sections: table<string, string[]>, order: string[], total: number }
local function collect_hits(doc, matches_line, max_results)
  local sections, order, total = {}, {}, 0
  local node_index = 1

  for number, line in ipairs(doc.lines) do
    while doc.nodes[node_index + 1] and doc.nodes[node_index + 1].line <= number do
      node_index = node_index + 1
    end
    if matches_line(line) then
      total = total + 1
      if total <= max_results then
        local node = doc.nodes[node_index]
        local key = node and node.path or "Preamble"
        if not sections[key] then
          sections[key] = {}
          table.insert(order, key)
        end
        table.insert(sections[key], fmt("  %d: %s", number, vim.trim(line)))
      end
    end
  end

  return { sections = sections, order = order, total = total }
end

---Search the doc, reporting each hit against the section that contains it
---@param doc table
---@param args { query: string, regex?: boolean }
---@param max_results number
---@return {status: "success"|"error", data: string}
local function run_search(doc, args, max_results)
  if not args.query or args.query == "" then
    return { status = "error", data = "The `search` command requires a `query` parameter" }
  end

  local matches_line, error_msg = build_matcher(args)
  if not matches_line then
    ---@cast error_msg string
    return { status = "error", data = error_msg }
  end

  local hits = collect_hits(doc, matches_line, max_results)
  if hits.total == 0 then
    return {
      status = "success",
      data = fmt(
        "No matches for `%s`. Try a broader term, or run the `outline` command to browse by topic.",
        args.query
      ),
    }
  end

  local blocks = vim.tbl_map(function(key)
    return fmt("%s\n%s", key, table.concat(hits.sections[key], "\n"))
  end, hits.order)

  local capped = hits.total > max_results and fmt(" (showing the first %d)", max_results) or ""
  return {
    status = "success",
    data = fmt(
      "%d matches for `%s` across %d sections%s.\n\n%s\n\nRead any of these in full with the `read` command and the section's heading path.",
      hits.total,
      args.query,
      #hits.order,
      capped,
      table.concat(blocks, "\n\n")
    ),
  }
end

---@class CodeCompanion.Tool.SearchHelp: CodeCompanion.Tools.Tool
return {
  name = "search_help",
  cmds = {
    ---@param self CodeCompanion.Tools
    ---@param args table The arguments from the LLM's tool call
    ---@return {status: "success"|"error", data: string}
    function(self, args)
      local doc, error_msg = load_doc()
      if not doc then
        log:error("[Search Help Tool] %s", error_msg)
        return { status = "error", data = error_msg }
      end

      local opts = self.tool and self.tool.opts or {}
      local command = args.command or "search"

      if command == "outline" then
        return run_outline(doc, args)
      end
      if command == "read" then
        return run_read(doc, args, opts.max_lines or 200)
      end
      if command == "search" then
        return run_search(doc, args, opts.max_results or 50)
      end

      return { status = "error", data = fmt("Unknown command: %s. Use `search`, `read` or `outline`.", command) }
    end,
  },
  schema = {
    type = "function",
    ["function"] = {
      name = "search_help",
      description = "Search CodeCompanion's own documentation. This is the authoritative source for how the plugin works - always consult it before answering questions about CodeCompanion's configuration, features or APIs, and never answer from memory."
        .. "\n* `search` finds a term across the docs and reports each hit against the section containing it."
        .. "\n* `read` returns a section verbatim, addressed by its heading path (e.g. `Configuration > CHAT BUFFER > KEYMAPS`) or its help tag."
        .. "\n* `outline` lists the document's headings, optionally scoped to one section."
        .. "\nStart with `search` when you have a term, or `outline` when you need to browse. Sections cross-reference each other with |help-tags| which you can pass straight back to `read`.",
      parameters = {
        type = "object",
        properties = {
          command = {
            type = "string",
            enum = { "search", "read", "outline" },
            description = "The operation to perform.",
          },
          query = {
            type = "string",
            description = "Required for `search`. Matched literally and case-insensitively unless `regex` is true.",
          },
          regex = {
            type = "boolean",
            description = "Optional for `search`. Treat the query as a case-sensitive Lua pattern rather than literal text.",
          },
          section = {
            type = "string",
            description = "Required for `read`, optional for `outline`. A heading path such as `Usage > CHAT BUFFER > KEYMAPS`, a trailing portion of one, or a help tag such as `codecompanion-usage-chat-buffer`.",
          },
          max_level = {
            type = "integer",
            description = "Optional for `outline`. How deep to descend the heading tree, from 1 to 4.",
          },
        },
        required = { "command" },
      },
    },
  },
  handlers = {
    ---@param self CodeCompanion.Tool.SearchHelp
    ---@param meta { tools: CodeCompanion.Tools }
    ---@return nil
    on_exit = function(self, meta)
      log:trace("[Search Help Tool] on_exit handler executed")
    end,
  },
  output = {
    ---@param self CodeCompanion.Tool.SearchHelp
    ---@param opts { tools: CodeCompanion.Tools }
    ---@return string
    cmd_string = function(self, opts)
      local args = self.args or {}
      return args.query or args.section or args.command or ""
    end,

    ---@param self CodeCompanion.Tool.SearchHelp
    ---@param stdout string[] The output from the command
    ---@param meta { tools: CodeCompanion.Tools, cmd: table }
    success = function(self, stdout, meta)
      meta.tools.chat:add_tool_output(self, stdout[1], "")
    end,

    ---@param self CodeCompanion.Tool.SearchHelp
    ---@param stderr table The error output from the command
    ---@param meta { tools: CodeCompanion.Tools, cmd: table }
    error = function(self, stderr, meta)
      local errors = vim.iter(stderr):flatten():join("\n")
      log:debug("[Search Help Tool] Error output: %s", stderr)
      meta.tools.chat:add_tool_output(self, errors)
    end,

    ---@param self CodeCompanion.Tool.SearchHelp
    ---@param meta { tools: CodeCompanion.Tools, cmd: string, opts: table }
    ---@return nil
    rejected = function(self, meta)
      meta = vim.tbl_extend("force", { message = "The user rejected the search help tool" }, meta or {})
      tool_helpers.rejected(self, meta)
    end,
  },
  system_prompt = function()
    local doc = load_doc()
    if not doc then
      return ""
    end

    local chapters = vim
      .iter(doc.nodes)
      :filter(function(node)
        return node.level <= 2
      end)
      :map(function(node)
        return render_heading(node, { indent = true })
      end)
      :totable()

    return fmt(
      "The `search_help` tool exposes CodeCompanion's own documentation, which is the authoritative source on "
        .. "the plugin. Consult it before answering any question about CodeCompanion rather than "
        .. "relying on your own knowledge, which may be out of date.\n\nGround every claim in what "
        .. "the tool returns and cite the heading path you took it from. If the docs do not cover "
        .. "something, say so rather than guessing.\n\nThe documentation is laid out as follows:\n\n%s",
      table.concat(chapters, "\n")
    )
  end,
}
