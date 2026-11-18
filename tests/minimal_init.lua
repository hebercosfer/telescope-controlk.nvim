local root = vim.fn.getcwd()
vim.opt.rtp:append(root)

local plenary = os.getenv("PLENARY_DIR") or vim.fn.expand("~/.local/share/nvim/lazy/plenary.nvim")
vim.opt.rtp:append(plenary)
vim.cmd("runtime plugin/plenary.vim")
