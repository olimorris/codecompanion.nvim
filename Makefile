all: format docs test

docs: deps/panvimdoc
	@echo Generating Docs...
	@pandoc \
		--metadata="project:codecompanion" \
		--metadata="vimversion:NVIM v0.10.0" \
		--metadata="titledatepattern:%Y %B %d" \
		--metadata="toc:true" \
		--metadata="incrementheadinglevelby:0" \
		--metadata="treesitter:true" \
		--metadata="dedupsubheadings:true" \
		--metadata="ignorerawblocks:true" \
		--metadata="docmapping:false" \
		--metadata="docmappingproject:true" \
		--lua-filter=deps/panvimdoc/scripts/include-files.lua \
		--lua-filter=deps/panvimdoc/scripts/skip-blocks.lua \
		--lua-filter scripts/panvimdoc-cleanup.lua \
		-t deps/panvimdoc/scripts/panvimdoc.lua \
		scripts/vimdoc.md \
		-o doc/codecompanion.txt

format:
	@echo Formatting...
	@stylua lua/ -f ./stylua.toml

test: deps
	@echo Testing...
	nvim --headless --noplugin -u ./scripts/minimal_init.lua -c "lua MiniTest.run()"

test_file: deps
	@echo Testing File...
	nvim --headless --noplugin -u ./scripts/minimal_init.lua -c "lua MiniTest.run_file('$(FILE)')"

plenary:
	@echo "===> Testing:"
	nvim --headless --clean \
	-u scripts/minimal_init.lua \
	-c "PlenaryBustedDirectory lua/spec/codecompanion { minimal_init = 'scripts/minimal_init.lua' }"

deps: deps/plenary.nvim deps/nvim-treesitter deps/mini.nvim deps/panvimdoc
	@echo Pulling...

deps/plenary.nvim:
	@mkdir -p deps
	git clone --filter=blob:none https://github.com/nvim-lua/plenary.nvim.git $@

deps/nvim-treesitter:
	@mkdir -p deps
	git clone --filter=blob:none https://github.com/nvim-treesitter/nvim-treesitter.git $@

deps/mini.nvim:
	@mkdir -p deps
	git clone --filter=blob:none https://github.com/echasnovski/mini.nvim $@

deps/panvimdoc:
	@mkdir -p deps
	git clone --filter=blob:none https://github.com/kdheepak/panvimdoc $@
