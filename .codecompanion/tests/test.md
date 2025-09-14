# Testing in CodeCompanion

The plugin uses a testing framework called [Mini.Test](https://github.com/nvim-mini/mini.test). The tests are written in Lua and are located in the `tests` directory. The tests are run using the `make test` command. The tests are written in a BDD style and are used to ensure the plugin is functioning as expected.

## Mini.Test

@.codecompanion/tests/mini_test_testing.md

A full overview of how Mini.Test works is included in the file above.

## Helpers

@./tests/helpers.lua

The plugin has some test helpers that allow for easier setting up of the plugin, additional assertion and some helper functions that come in handy.

## Example Screenshot Test

@./tests/adapters/http/test_tools_in_chat_buffer.lua

One of Mini.Tests unique selling points is its ability to allow for screenshot tests. That is, you can assert that Neovim looks as expected.
