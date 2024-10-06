PANVIMDOC_DIR = misc/panvimdoc
PANVIMDOC_URL = https://github.com/kdheepak/panvimdoc
PLENARY_DIR = misc/plenary
PLENARY_URL = https://github.com/nvim-lua/plenary.nvim
TREESITTER_DIR = misc/treesitter
TREESITTER_URL = https://github.com/nvim-treesitter/nvim-treesitter

all: format test docs tools adapters recipes

docs: $(PANVIMDOC_DIR)
	@echo "===> Docs:" && \
	cd $(PANVIMDOC_DIR) && \
	pandoc \
		--metadata="project:codecompanion" \
		--metadata="vimversion:NVIM v0.10.0" \
		--metadata="titledatepattern:%Y %B %d" \
		--metadata="toc:true" \
		--metadata="incrementheadinglevelby:0" \
		--metadata="treesitter:true" \
		--lua-filter scripts/skip-blocks.lua \
		--lua-filter scripts/include-files.lua \
		--lua-filter scripts/remove-emojis.lua \
		-t scripts/panvimdoc.lua \
		../../README.md \
		-o ../../doc/codecompanion.txt

tools: $(PANVIMDOC_DIR)
	@echo "===> Tools:" && \
	cd $(PANVIMDOC_DIR) && \
	pandoc \
		--metadata="project:codecompanion-tools" \
		--metadata="vimversion:NVIM v0.10.0" \
		--metadata="titledatepattern:%Y %B %d" \
		--metadata="toc:true" \
		--metadata="incrementheadinglevelby:0" \
		--metadata="treesitter:true" \
		--lua-filter scripts/skip-blocks.lua \
		--lua-filter scripts/include-files.lua \
		--lua-filter scripts/remove-emojis.lua \
		-t scripts/panvimdoc.lua \
		../../doc/TOOLS.md \
		-o ../../doc/codecompanion-tools.txt

adapters: $(PANVIMDOC_DIR)
	@echo "===> Adapters:" && \
	cd $(PANVIMDOC_DIR) && \
	pandoc \
			--metadata="project:codecompanion-adapters" \
			--metadata="vimversion:NVIM v0.10.0" \
		--metadata="titledatepattern:%Y %B %d" \
		--metadata="toc:true" \
		--metadata="incrementheadinglevelby:0" \
		--metadata="treesitter:true" \
		--lua-filter scripts/skip-blocks.lua \
		--lua-filter scripts/include-files.lua \
		--lua-filter scripts/remove-emojis.lua \
		-t scripts/panvimdoc.lua \
		../../doc/ADAPTERS.md \
		-o ../../doc/codecompanion-adapters.txt

recipes: $(PANVIMDOC_DIR)
	@echo "===> Recipes:" && \
	cd $(PANVIMDOC_DIR) && \
	pandoc \
		--metadata="project:codecompanion-recipes" \
		--metadata="vimversion:NVIM v0.10.0" \
		--metadata="titledatepattern:%Y %B %d" \
		--metadata="toc:true" \
		--metadata="incrementheadinglevelby:0" \
		--metadata="treesitter:true" \
		--lua-filter scripts/skip-blocks.lua \
		--lua-filter scripts/include-files.lua \
		--lua-filter scripts/remove-emojis.lua \
		-t scripts/panvimdoc.lua \
		../../doc/RECIPES.md \
		-o ../../doc/codecompanion-recipes.txt

$(PANVIMDOC_DIR):
	git clone --depth=1 --no-single-branch $(PANVIMDOC_URL) $(PANVIMDOC_DIR)
	@rm -rf doc/panvimdoc/.git

format:
	@echo "===> Formatting:"
	@stylua lua/ -f ./stylua.toml

test: $(PLENARY_DIR) $(TREESITTER_DIR)
	@echo "===> Testing:"
	nvim --headless --clean \
	-u scripts/minimal.vim \
	-c "PlenaryBustedDirectory lua/spec/codecompanion { minimal_init = 'scripts/minimal.vim' }"

$(PLENARY_DIR):
	git clone --depth=1 $(PLENARY_URL) $(PLENARY_DIR)
	@rm -rf $(PLENARY_DIR)/.git

$(TREESITTER_DIR):
	git clone --depth=1 $(TREESITTER_URL) $(TREESITTER_DIR)
	@rm -rf $(TREESITTER_DIR)/.git
