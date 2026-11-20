local root = vim.fn.getcwd()
-- Before any plugin loads, so every vim.deprecate call goes through the hook.
dofile(root .. "/tests/support/deprecations.lua").install(root, os.getenv("DEPRECATION_REPORT"))
vim.opt.rtp:append(root)
-- Plugin managers generate doc/tags; the specs need it to find controlk's help tags.
vim.cmd.helptags(root .. "/doc")

local plenary = os.getenv("PLENARY_DIR") or vim.fn.expand("~/.local/share/nvim/lazy/plenary.nvim")
vim.opt.rtp:append(plenary)
vim.cmd("runtime plugin/plenary.vim")
