return {
  -- change some telescope options and a keymap to browse plugin files
  {
    "nvim-telescope/telescope.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-telescope/telescope-live-grep-args.nvim",
      "nvim-tree/nvim-web-devicons",
    },
    keys = {
      -- add a keymap to browse plugin files
      -- stylua: ignore
     {
        "<leader>fp",
        function() require("telescope.builtin").find_files({ cwd = require("lazy.core.config").options.root }) end,
        desc = "Find Plugin File",
      },
    },
    -- change some options
    opts = {
      defaults = {
        layout_strategy = "horizontal",
        layout_config = { prompt_position = "top" },
        sorting_strategy = "ascending",
        winblend = 0,
      },
    },
  },
  -- dressing (pulled in by the telescope extra) sizes input boxes to the current window,
  -- so prompts opened from narrow windows (e.g. Diffview's file list) get squeezed. Use the whole screen.
  {
    "stevearc/dressing.nvim",
    opts = {
      input = {
        relative = "editor",
        prefer_width = 72,
      },
    },
  },
}
