local root = vim.fn.getcwd()
-- Before any plugin loads, so every vim.deprecate call goes through the hook.
dofile(root .. "/tests/support/deprecations.lua").install(root, os.getenv("DEPRECATION_REPORT"))
vim.opt.rtp:append(root)
-- Plugin managers generate doc/tags; the specs need it to find controlk's help tags.
vim.cmd.helptags(root .. "/doc")

local plenary = os.getenv("PLENARY_DIR") or vim.fn.expand("~/.local/share/nvim/lazy/plenary.nvim")
-- Without plenary, PlenaryBustedDirectory is an unknown command and headless Neovim waits at
-- the error forever. Fail at once instead.
if vim.fn.isdirectory(plenary) == 0 then
  io.stderr:write("minimal_init: plenary.nvim not found at " .. plenary .. " (set PLENARY_DIR)\n")
  vim.cmd("cquit 1")
end
vim.opt.rtp:append(plenary)
vim.cmd("runtime plugin/plenary.vim")
