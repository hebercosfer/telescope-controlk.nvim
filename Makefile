.PHONY: test test-integration check-deprecations lint format

# Set on the command line, or per CI matrix leg. Not NVIM: inside a Neovim
# :terminal that variable already holds the server socket.
NVIM_BIN ?= nvim
PLENARY_DIR ?= $(HOME)/.local/share/nvim/lazy/plenary.nvim
TELESCOPE_DIR ?= $(HOME)/.local/share/nvim/lazy/telescope.nvim
FZF_DIR ?= $(HOME)/.local/share/nvim/lazy/telescope-fzf-native.nvim
STYLUA ?= stylua
LUACHECK ?= luacheck
# Where the integration sessions record deprecated calls made by Neovim or the plugins, and
# the list of those that are known and accepted. See tests/check_deprecations.lua.
DEPRECATION_REPORT ?= .tests/deprecations.log
DEPRECATION_ALLOW ?= tests/deprecations-allow.txt

# Unit specs. Telescope is not on the runtimepath here.
test:
	PLENARY_DIR='$(PLENARY_DIR)' $(NVIM_BIN) --headless -u tests/minimal_init.lua \
		-c "PlenaryBustedDirectory tests/ { minimal_init = 'tests/minimal_init.lua', sequential = true }"

# The integration harness drives the real picker in two sessions. It also loads
# telescope-fzf-native, as many configurations do. A failed check exits non-zero.
# Both sessions append to one deprecation report, checked once they are done.
# run.lua quits on its own when it finishes. The cquit after it runs only when the script
# stopped on an error, which would otherwise leave headless Neovim waiting forever.
test-integration:
	mkdir -p $(dir $(DEPRECATION_REPORT))
	rm -f $(DEPRECATION_REPORT)
	for session in lsp config; do \
		DEPRECATION_REPORT='$(DEPRECATION_REPORT)' SESSION=$$session FZF=1 \
			$(NVIM_BIN) --headless -u NONE \
			--cmd "set rtp+=$(CURDIR),$(TELESCOPE_DIR),$(PLENARY_DIR),$(FZF_DIR)" \
			-c "luafile tests/integration/run.lua" -c "cquit 2" \
			|| { echo "Neovim exited with $$? (session $$session)"; exit 1; }; \
	done
	$(MAKE) --no-print-directory check-deprecations

# Fails on any reported deprecation that the allow-list does not name.
check-deprecations:
	DEPRECATION_REPORT='$(DEPRECATION_REPORT)' DEPRECATION_ALLOW='$(DEPRECATION_ALLOW)' \
		$(NVIM_BIN) -l tests/check_deprecations.lua

lint:
	$(STYLUA) --check .
	$(LUACHECK) lua tests

format:
	$(STYLUA) .
