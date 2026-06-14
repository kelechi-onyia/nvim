return {
  {
    "MeanderingProgrammer/render-markdown.nvim",
    ft = { "markdown" },
    opts = {
      heading = {
        -- Disable heading backgrounds and icons
        enabled = true,
        backgrounds = {},
      },
      code = {
        sign = true,
        width = "block",
        right_pad = 10,
        language = true,
        language_icon = false,
        language_name = false,
        language_info = true,
        render_modes = true,
      },
    },
  },
}
