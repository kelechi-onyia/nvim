vim.opt.backspace = "2"
vim.opt.showcmd = true
vim.opt.laststatus = 2
vim.opt.autowrite = true
vim.opt.cursorline = true
vim.opt.autoread = true

-- Use spaces for tabs and whatnot
vim.opt.tabstop = 2
vim.opt.shiftwidth = 2
vim.opt.shiftround = true
vim.opt.expandtab = true

vim.keymap.set("n", "<leader>h", ":nohlsearch<CR>")

--  markdown preview in a browser
vim.keymap.set("n", "<leader>pu", ":MarkdownPreview<CR>")
vim.keymap.set("n", "<leader>ps", ":MarkdownPreviewStop<CR>")

-- show line when nvim is open
vim.wo.relativenumber = true
