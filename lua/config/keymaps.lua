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

-- keep side-by-side diffs in sync when scrolling with the mouse: Neovim ignores scrollbind
-- when the wheel scrolls a window that isn't the current one, so scroll it as if it were
local function bound_wheel(key, scroll, axis)
  return function()
    local win = vim.fn.getmousepos().winid
    if win ~= 0 and vim.wo[win].scrollbind then
      local n = tonumber(vim.o.mousescroll:match(axis .. ":(%d+)")) or (axis == "ver" and 3 or 6)
      vim.api.nvim_win_call(win, function()
        vim.cmd("normal! " .. n .. scroll)
      end)
      -- scrollbind doesn't sync horizontal scrolls made this way, so copy leftcol over
      if axis == "hor" then
        local leftcol = vim.api.nvim_win_call(win, vim.fn.winsaveview).leftcol
        for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
          if w ~= win and vim.wo[w].scrollbind and not vim.wo[w].wrap then
            vim.api.nvim_win_call(w, function()
              vim.fn.winrestview({ leftcol = leftcol })
            end)
          end
        end
      end
    else
      vim.api.nvim_feedkeys(vim.keycode(key), "n", false)
    end
  end
end
for key, spec in pairs({
  ["<ScrollWheelDown>"] = { "\5", "ver" }, -- <C-e>
  ["<ScrollWheelUp>"] = { "\25", "ver" }, -- <C-y>
  ["<ScrollWheelRight>"] = { "zl", "hor" },
  ["<ScrollWheelLeft>"] = { "zh", "hor" },
}) do
  vim.keymap.set({ "n", "i" }, key, bound_wheel(key, spec[1], spec[2]), { desc = "Mouse scroll (synced in diffs)" })
end

-- show line when nvim is open
vim.wo.relativenumber = true

-- nvim-tree configuration
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

-- optionally enable 24-bit colour
vim.opt.termguicolors = true

vim.keymap.set("n", "<c-n>", ":NvimTreeToggle<CR>")
vim.keymap.set("n", "<c-m>", ":NvimTreeFindFile<CR>")

vim.keymap.set({ "n", "i", "x" }, "<Cmd-s>", ":w<CR>", { desc = "Save File", silent = true })
