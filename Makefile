.PHONY: test test-integration lint format

# Set on the command line, or per CI matrix leg. Not NVIM: inside a Neovim
# :terminal that variable already holds the server socket.
NVIM_BIN ?= nvim
PLENARY_DIR ?= $(HOME)/.local/share/nvim/lazy/plenary.nvim
TELESCOPE_DIR ?= $(HOME)/.local/share/nvim/lazy/telescope.nvim
FZF_DIR ?= $(HOME)/.local/share/nvim/lazy/telescope-fzf-native.nvim
STYLUA ?= stylua
LUACHECK ?= luacheck

# Unit specs. Telescope is not on the runtimepath here.
test:
	PLENARY_DIR=$(PLENARY_DIR) $(NVIM_BIN) --headless -u tests/minimal_init.lua \
		-c "PlenaryBustedDirectory tests/ { minimal_init = 'tests/minimal_init.lua', sequential = true }"

# The integration harness drives the real picker in two sessions. It also loads
# telescope-fzf-native, as the owner's config does. A failed check exits non-zero.
test-integration:
	for session in lsp config; do \
		SESSION=$$session FZF=1 $(NVIM_BIN) --headless -u NONE \
			--cmd "set rtp+=$(CURDIR),$(TELESCOPE_DIR),$(PLENARY_DIR),$(FZF_DIR)" \
			-c "luafile tests/integration/run.lua" || exit 1; \
	done

lint:
	$(STYLUA) --check .
	$(LUACHECK) lua tests

format:
	$(STYLUA) .
