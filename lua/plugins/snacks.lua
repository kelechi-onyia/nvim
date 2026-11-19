return {
  "folke/snacks.nvim",
  keys = {
    -- Ctrl+- toggles the terminal too (iTerm2 sends it as its own key, not Ctrl+_)
    {
      "<C-->",
      function() Snacks.terminal.focus(nil, { cwd = LazyVim.root() }) end,
      mode = { "n", "t" },
      desc = "Terminal (Root Dir)",
    },
  },
  opts = {
    terminal = {
      win = {
        position = "float",
      },
    },
    -- full-screen lazygit so side-by-side diffs have room
    lazygit = {
      win = { width = 0, height = 0 },
    },
  },
}
