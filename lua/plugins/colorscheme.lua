return {
  -- Catppuccin colorscheme
  {
    "catppuccin/nvim",
    lazy = true,
    name = "catppuccin",
    priority = 1000,
    opts = {
      flavour = "macchiato", -- latte, frappe, macchiato, mocha

      lsp_styles = {
        underlines = {
          errors = { "undercurl" },
          hints = { "undercurl" },
          warnings = { "undercurl" },
          information = { "undercurl" },
        },
      },
    },
  },

  -- Set it as the active colorscheme
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "catppuccin",
    },
  },
}
