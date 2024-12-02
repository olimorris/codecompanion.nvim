local Helpers = {}

Helpers.expect = MiniTest.expect --[[@type function]]
Helpers.eq = MiniTest.expect.equality --[[@type function]]
Helpers.not_eq = MiniTest.expect.no_equality --[[@type function]]

return Helpers
