return {
  "nvim-tree/nvim-tree.lua",
  version = "*",
  lazy = false,
  dependencies = {
    "nvim-tree/nvim-web-devicons",
  },
  config = function()
    -- OR setup with some options
    require("nvim-tree").setup({
      sort = {
        sorter = "case_sensitive",
      },
      view = {
        width = 30,
        adaptive_size = true,
      },
      renderer = {
        group_empty = false,
        icons = {
          show = {
            git = true,
          },
        },
      },
      filters = {
        dotfiles = false,
      },
      git = {
        ignore = false,
        enable = true,
      },
    })

    -- nvim-tree doesn't redraw git signs for changes made while its tab isn't current
    -- (e.g. commit/push in Diffview, which has its own tab), so re-read them on return
    vim.api.nvim_create_autocmd({ "TabEnter", "FocusGained" }, {
      group = vim.api.nvim_create_augroup("nvim_tree_git_refresh", { clear = true }),
      callback = function()
        local api = require("nvim-tree.api")
        if api.tree.is_visible() then
          api.tree.reload()
        end
      end,
    })
  end,
}
