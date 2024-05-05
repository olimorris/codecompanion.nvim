local function init()
    return {
        options = {commentNode=1, piNode=1, dtdNode=1, declNode=1},
        current = { _children = {}, _type = "ROOT" },
        _stack = {}
    }
end

--- @module Handler to generate a DOM-like node tree structure with
--      a single ROOT node parent - each node is a table comprising
--      the fields below.
--
--      node = { _name = <ELEMENT Name>,
--              _type = ROOT|ELEMENT|TEXT|COMMENT|PI|DECL|DTD,
--              _text = <TEXT or COMMENT string>,
--              _attr = { Node attributes - see callback API },
--              _parent = <Parent Node>,
--              _children = { List of child nodes - ROOT/ELEMENT only }
--            }
--      where:
--      - PI = XML Processing Instruction tag.
--      - DECL = XML declaration tag
--
--      The dom structure is capable of representing any valid XML document
--
-- Options
-- =======
--    options.(comment|pi|dtd|decl)Node = bool
--        - Include/exclude given node types
--
--  License:
--  ========
--
--      This code is freely distributable under the terms of the [MIT license](LICENSE).
--
--@author Paul Chakravarti (paulc@passtheaardvark.com)
--@author Manoel Campos da Silva Filho
local dom = init()

---Instantiates a new handler object.
--Each instance can handle a single XML.
--By using such a constructor, you can parse
--multiple XML files in the same application.
--@return the handler instance
function dom:new()
    local obj = init()

    obj.__index = self
    setmetatable(obj, self)

    return obj
end

---Parses a start tag.
-- @param tag a {name, attrs} table
-- where name is the name of the tag and attrs
-- is a table containing the attributes of the tag
function dom:starttag(tag)
    local node = { _type = 'ELEMENT',
                   _name = tag.name,
                   _attr = tag.attrs,
                   _children = {}
                 }

    if not self.root then
        self.root = node
    end

    table.insert(self._stack, node)

    table.insert(self.current._children, node)
    self.current = node
end

---Parses an end tag.
-- @param tag a {name, attrs} table
-- where name is the name of the tag and attrs
-- is a table containing the attributes of the tag
function dom:endtag(tag)
    --Table representing the containing tag of the current tag
    local prev = self._stack[#self._stack]

    if tag.name ~= prev._name then
        error("XML Error - Unmatched Tag ["..s..":"..tag.name.."]\n")
    end

    table.remove(self._stack)
    self.current = self._stack[#self._stack]
    if not self.current then
       local node = { _children = {}, _type = "ROOT" }
       if self.decl then
	  table.insert(node._children, self.decl)
	  self.decl = nil
       end
       if self.dtd then
	  table.insert(node._children, self.dtd)
	  self.dtd = nil
       end
       if self.root then
	  table.insert(node._children, self.root)
	  self.root = node
       end
       self.current = node
    end
end

---Parses a tag content.
-- @param text text to process
function dom:text(text)
    local node = { _type = "TEXT",
                   _text = text
                 }
    table.insert(self.current._children, node)
end

---Parses a comment tag.
-- @param text comment text
function dom:comment(text)
    if self.options.commentNode then
        local node = { _type = "COMMENT",
                       _text = text
                     }
        table.insert(self.current._children, node)
    end
end

--- Parses a XML processing instruction (PI) tag
-- @param tag a {name, attrs} table
-- where name is the name of the tag and attrs
-- is a table containing the attributes of the tag
function dom:pi(tag)
    if self.options.piNode then
        local node = { _type = "PI",
                       _name = tag.name,
                       _attr = tag.attrs,
                     }
        table.insert(self.current._children, node)
    end
end

---Parse the XML declaration line (the line that indicates the XML version).
-- @param tag a {name, attrs} table
-- where name is the name of the tag and attrs
-- is a table containing the attributes of the tag
function dom:decl(tag)
   if self.options.declNode then
      self.decl = { _type = "DECL",
		    _name = tag.name,
		    _attr = tag.attrs,
      }
   end
end

---Parses a DTD tag.
-- @param tag a {name, value} table
-- where name is the name of the tag and value
-- is a table containing the attributes of the tag
function dom:dtd(tag)
   if self.options.dtdNode then
      self.dtd = { _type = "DTD",
		   _name = tag.name,
		   _text = tag.value
      }
   end
end

--- XML escape characters for a TEXT node.
-- @param s a string
-- @return @p s XML escaped.
local function xmlEscape(s)
   s = string.gsub(s, '&', '&amp;')
   s = string.gsub(s, '<', '&lt;')
   return string.gsub(s, '>', '&gt;')
end

--- return a string of XML attributes
-- @param tab table with XML attribute pairs. key and value are supposed to be strings.
-- @return a string.
local function attrsToStr(tab)
   if not tab then
      return ''
   end
   if type(tab) == 'table' then
      local s = ''
      for n,v in pairs(tab) do
	 -- determine a safe quote character
	 local val = tostring(v)
	 local found_single_quote = string.find(val, "'")
	 local found_double_quote = string.find(val, '"')
	 local quot = '"'
	 if found_single_quote and found_double_quote then
	    -- XML escape both quote characters
	    val = string.gsub(val, '"', '&quot;')
	    val = string.gsub(val, "'", '&apos;')
	 elseif found_double_quote then
	    quot = "'"
	 end
	 s = ' ' .. tostring(n) .. '=' .. quot .. val .. quot
      end
      return s
   end
   return 'BUG:unknown type:' .. type(tab)
end

--- return a XML formatted string of @p node.
-- @param node a Node object (table) of the xml2lua DOM tree structure.
-- @return a string.
local function toXmlStr(node, indentLevel)
   if not node then
      return 'BUG:node==nil'
   end
   if not node._type then
      return 'BUG:node._type==nil'
   end

   local indent = ''
   for i=0, indentLevel+1, 1 do
      indent = indent .. ' '
   end

   if node._type == 'ROOT' then
      local s = ''
      for i, n in pairs(node._children) do
	 s = s .. toXmlStr(n, indentLevel+2)
      end
      return s
   elseif node._type == 'ELEMENT' then
      local s = indent .. '<' .. node._name .. attrsToStr(node._attr)

      -- check if ELEMENT has no children
      if not node._children or
	 #node._children == 0 then
	 return s .. '/>\n'
      end

      s = s .. '>\n'

      for i, n in pairs(node._children) do
	 local xx = toXmlStr(n, indentLevel+2)
	 if not xx then
	    print('BUG:xx==nil')
	 else
	    s = s .. xx
	 end
      end

      return s .. indent .. '</' .. node._name .. '>\n'

   elseif node._type == 'TEXT' then
      return indent .. xmlEscape(node._text) .. '\n'
   elseif node._type == 'COMMENT' then
      return indent .. '<!--' .. node._text .. '-->\n'
   elseif node._type == 'PI' then
      return indent .. '<?' .. node._name .. ' ' .. node._attr._text .. '?>\n'
   elseif node._type == 'DECL' then
      return indent .. '<?' .. node._name .. attrsToStr(node._attr) .. '?>\n'
   elseif node._type == 'DTD' then
      return indent .. '<!' .. node._name .. ' ' .. node._text .. '>\n'
   end
   return 'BUG:unknown type:' .. tostring(node._type)
end

---create a string in XML format from the dom root object @p node.
-- @param node a root object, typically created with `dom` XML parser handler.
-- @return a string, XML formatted.
function dom:toXml(node)
   return toXmlStr(node, -4)
end

---Parses CDATA tag content.
dom.cdata = dom.text
dom.__index = dom
return dom
