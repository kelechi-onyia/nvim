return {

  -- add any tools you want to have installed below
  {
    "williamboman/mason.nvim",
    opts = {
      ensure_installed = {
        "stylua",
        "shellcheck",
        "shfmt",
        "flake8",
        "alex",
        "alhelm-ls",
        "helm_ls",
        "aljson-lsp",
        "jsonls",
        "allua-language-server",
        "lua_ls",
        "almarkdownlint",
        "alprettier",
        "alpylint",
        "alpyright",
        "alpython-lsp-server",
        "pylsp",
        "alshellcheck",
        "alshfmt",
        "alstylua",
        "alvtsls",
      },
    },
  },
}
