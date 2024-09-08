-- if true then
--   return {}
-- end

return {

  -- add any tools you want to have installed below
  {
    "williamboman/mason.nvim",
    opts = {
      ensure_installed = {
        "pyright",
        "templ",
        "actionlint",
        "ansible-language-server",
        "ansible-lint",
        "bash-language-server",
        "beautysh",
        "docker-compose-language-service",
        "dockerfile-language-server",
        "golangci-lint-langserver",
        "helm-ls",
        "html-lsp",
        "htmlbeautifier",
        "lua-language-server",
        "markdownlint",
        "npm-groovy-lint",
        "opa",
        "prettier",
        "prettierd",
        "regal",
        "regols",
        "shellcheck",
        "shfmt",
        "snyk",
        "sonarlint-language-server",
        "stylua",
        "termux-language-server",
        "terraform-ls",
        "trivy",
        "typescript-language-server",
        "vtsls",
        "yaml-language-server",
        "yamlfix",
        "yamlfmt",
        "yamllint",
        "yq",
        "usort",
      },
    },
  },
}
