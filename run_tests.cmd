@ECHO OFF
SETLOCAL

CD %~dp0

REM test_adapters.lua check the %HOME% env var, which isn't normally there
REM on native Windows, and it's much easier to make sure it's set than
REM to muck about in Lua itself.
IF [%HOME%] == [] SET "HOME=%HOMEDRIVE%%HOMEPATH%"

REM set up dependencies
IF NOT EXIST deps MD deps
IF NOT EXIST deps\plenary.nvim git clone --filter=blob:none https://github.com/nvim-lua/plenary.nvim.git deps\plenary.nvim
IF NOT EXIST deps\nvim-treesitter git clone --filter=blob:none https://github.com/nvim-treesitter/nvim-treesitter.git deps\nvim-treesitter
IF NOT EXIST deps\mini.nvim git clone --filter=blob:none https://github.com/echasnovski/mini.nvim.git deps\mini.nvim
IF NOT EXIST deps\panvimdoc git clone --filter=blob:none https://github.com/kdheepak/panvimdoc.git deps\panvimdoc

REM If an argument is specified, run a single test

IF [%1] == [] GOTO :ALL_TESTS
nvim --headless --noplugin -u ./scripts/minimal_init.lua -c "lua MiniTest.run_file('%1')"
EXIT /B %ERRORLEVEL%

:ALL_TESTS
nvim --headless --noplugin -u ./scripts/minimal_init.lua -c "lua MiniTest.run()"
EXIT /B %ERRORLEVEL%
