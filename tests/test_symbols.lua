local new_set = MiniTest.new_set
local T = new_set()
T["Symbols"] = new_set({})

local python = [[
class Product:
    def __init__(self, name: str, price: float, quantity: int = 0):
        self._name = name
        self._price = price
        self._quantity = quantity

    @property
    def name(self) -> str:
        return self._name

    @name.setter
    def name(self, value: str) -> None:
        if not value:
            raise ValueError("Name cannot be empty")
        self._name = value

    @property
    def price(self) -> float:
        return self._price

    @price.setter
    def price(self, value: float) -> None:
        if value < 0:
            raise ValueError("Price cannot be negative")
        self._price = value

    def calculate_total(self) -> float:
        return self._price * self._quantity

    def __str__(self) -> str:
        return f"Product(name={self._name}, price=${self._price:.2f}, quantity={self._quantity})"

    def add_stock(self, amount: int) -> None:
        if amount < 0:
            raise ValueError("Amount cannot be negative")
        self._quantity += amount

print("Product.__annotations__:", Product.__annotations__)
]]

T["Symbols"]["can be parsed"] = function()
  local query = vim.treesitter.query.get("python", "symbols")

  local parser = vim.treesitter.get_string_parser(python, "python")
  local root = parser:parse()[1]:root()

  for _, matches, metadata in query:iter_matches(root, python) do
    local match = vim.tbl_extend("force", {}, metadata)
    for id, nodes in pairs(matches) do
      -- Handle nodes as a list (the new behavior)
      local node = type(nodes) == "table" and nodes[1] or nodes
      match = vim.tbl_extend("keep", match, {
        [query.captures[id]] = {
          metadata = metadata[id],
          node = node,
        },
      })
    end
    -- Where name is a capture group in the query
    -- local output = vim.treesitter.get_node_text(match.name.node, python)
    -- print("\n", output)
    local start_row, _, end_row, _ = vim.treesitter.get_node_range(match.name.node)
    -- print("\n", start_row, end_row)
  end
  -- print("\n")
end

return T
