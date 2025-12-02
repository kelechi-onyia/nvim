-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
-- Add any additional autocmds here

-- Remove markdown header highlighting
vim.api.nvim_create_autocmd("FileType", {
  pattern = "markdown",
  callback = function()
    -- Clear highlighting for all markdown headers
    vim.cmd([[
      highlight clear @markup.heading.1.markdown
      highlight clear @markup.heading.2.markdown
      highlight clear @markup.heading.3.markdown
      highlight clear @markup.heading.4.markdown
      highlight clear @markup.heading.5.markdown
      highlight clear @markup.heading.6.markdown
      highlight clear markdownH1
      highlight clear markdownH2
      highlight clear markdownH3
      highlight clear markdownH4
      highlight clear markdownH5
      highlight clear markdownH6
    ]])
  end,
})
