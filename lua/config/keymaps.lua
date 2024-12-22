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
vim.keymap.set("n", "<leader>Pu", ":MarkdownPreview<CR>", { desc = "Show MarkdownPreview", silent = true })
vim.keymap.set("n", "<leader>Ps", ":MarkdownPreviewStop<CR>", { desc = "Stop MarkdownPreview", silent = true })

-- compare files
vim.keymap.set("n", "<leader>fd", ":windo diffthis<CR>", { desc = "file diff", silent = true })
vim.keymap.set("n", "<leader>fx", ":windo diffoff<CR>", { desc = "diff off", silent = true })
vim.keymap.set("n", "<leader>fs", ":diffsplit<CR>", { desc = "diff split", silent = true })

-- show line when nvim is open
vim.wo.relativenumber = true

-- nvim-tree configuration
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

-- optionally enable 24-bit colour
vim.opt.termguicolors = true

-- vim.keymap.set("n", "<c-n>", ":NvimTreeToggle<CR>")
-- vim.keymap.set("n", "<c-m>", ":NvimTreeFindFile<CR>")
