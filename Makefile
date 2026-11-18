.PHONY: lint format

# The owner's stylua config is .stylua.toml in the repository root.
STYLUA ?= stylua
LUACHECK ?= luacheck

lint:
	$(STYLUA) --check .
	$(LUACHECK) lua tests

format:
	$(STYLUA) .
