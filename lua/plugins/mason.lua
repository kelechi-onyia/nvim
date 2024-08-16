if true then
  return {}
end

return {

  -- add any tools you want to have installed below
  {
    "williamboman/mason.nvim",
    opts = {
      ensure_installed = {
        "alex",
        "angular-language-server",
        "ansible-language-server",
        "ansible-lint",
        "azure-pipelines-language-server",
        "css-variables-language-server",
        "docker-compose-language-service",
        "dockerfile-language-server",
        "gradle-language-server",
        "graphql-language-service-cli",
        "helm-ls",
        "htmlhint",
        "jsonlint",
        "kotlin-language-server",
        "lua-language-server",
        "luacheck",
        "markdownlint",
        "pylint",
        "pyright",
        "python-lsp-server",
        "shellcheck",
        "sql-formatter",
        "sqlfmt",
        "stylelint",
        "stylua",
        "usort",
        "yaml-language-server",
        "yamllint",
      },
    },
  },
}
