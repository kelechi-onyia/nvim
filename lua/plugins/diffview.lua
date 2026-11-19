-- VS Code-style side-by-side git diff

-- git helpers so you can commit and push without leaving Diffview
local function repo_root()
  local view = require("diffview.lib").get_current_view()
  return view and view.adapter.ctx.toplevel or vim.fn.getcwd()
end

local function git(root, args, on_ok)
  vim.system(
    vim.list_extend({ "git" }, args),
    { text = true, cwd = root, env = { GIT_TERMINAL_PROMPT = "0" } },
    function(r)
      vim.schedule(function()
        if r.code ~= 0 then
          local err = vim.trim(r.stderr ~= "" and r.stderr or r.stdout)
          vim.notify(err, vim.log.levels.ERROR, { title = "git " .. args[1] })
        elseif on_ok then
          on_ok(r)
        end
      end)
    end
  )
end

local function commit()
  local root = repo_root()
  local function do_commit()
    vim.ui.input({ prompt = "Commit message: " }, function(msg)
      if not msg or vim.trim(msg) == "" then
        return
      end
      git(root, { "commit", "-m", msg }, function(r)
        vim.notify(vim.split(r.stdout, "\n")[1], vim.log.levels.INFO, { title = "git commit" })
        vim.cmd("DiffviewRefresh")
      end)
    end)
  end
  -- like VS Code: if nothing is staged, offer to stage everything first
  vim.system({ "git", "diff", "--cached", "--quiet" }, { cwd = root }, function(r)
    vim.schedule(function()
      if r.code == 1 then
        return do_commit()
      end
      vim.ui.select({ "Stage all changes and commit", "Cancel" }, { prompt = "Nothing staged" }, function(choice)
        if choice and choice:match("^Stage") then
          git(root, { "add", "-A" }, do_commit)
        end
      end)
    end)
  end)
end

local function push()
  local root = repo_root()
  vim.notify("Pushing…", vim.log.levels.INFO, { title = "git push" })
  -- first push of a new branch: set the upstream automatically
  vim.system({ "git", "rev-parse", "--abbrev-ref", "@{u}" }, { cwd = root }, function(r)
    local args = r.code == 0 and { "push" } or { "push", "-u", "origin", "HEAD" }
    vim.schedule(function()
      git(root, args, function()
        vim.notify("Pushed", vim.log.levels.INFO, { title = "git push" })
        vim.cmd("DiffviewRefresh")
      end)
    end)
  end)
end

local function pull()
  local root = repo_root()
  vim.notify("Pulling…", vim.log.levels.INFO, { title = "git pull" })
  git(root, { "pull" }, function(r)
    -- first and last line, e.g. "Updating a..b" + "2 files changed, ..."
    local lines = vim.split(vim.trim(r.stdout), "\n")
    local msg = #lines > 1 and (lines[1] .. "\n" .. vim.trim(lines[#lines])) or lines[1]
    vim.notify(msg, vim.log.levels.INFO, { title = "git pull" })
    vim.cmd("DiffviewRefresh")
  end)
end

return {
  "sindrets/diffview.nvim",
  cmd = { "DiffviewOpen", "DiffviewClose", "DiffviewFileHistory", "DiffviewToggleFiles" },
  keys = {
    {
      "<leader>gv",
      function()
        if next(require("diffview.lib").views) == nil then
          vim.cmd("DiffviewOpen")
        else
          vim.cmd("DiffviewClose")
        end
      end,
      desc = "Diffview Toggle (working tree)",
    },
    { "<leader>gV", "<cmd>DiffviewFileHistory %<cr>", desc = "Diffview File History" },
    { "<leader>gm", "<cmd>DiffviewOpen origin/HEAD...HEAD<cr>", desc = "Diffview vs main (PR review)" },
  },
  init = function()
    -- better line alignment and word-level highlights inside changed lines
    vim.opt.diffopt:append({ "algorithm:histogram", "linematch:60" })

    -- Called from lazygit (<c-v>): hide the lazygit float and open Diffview.
    -- lazygit keeps running hidden, so <leader>gg brings you back where you were.
    function _G.LazygitDiffview(root, rev, path)
      vim.schedule(function()
        for _, win in ipairs(vim.api.nvim_list_wins()) do
          local buf = vim.api.nvim_win_get_buf(win)
          if vim.bo[buf].buftype == "terminal" and vim.api.nvim_buf_get_name(buf):find("lazygit") then
            vim.api.nvim_win_close(win, true)
          end
        end
        local args = { "DiffviewOpen", "-C" .. vim.fn.fnameescape(root) }
        if rev ~= "" then
          table.insert(args, rev)
        end
        if path ~= "" then
          table.insert(args, "--selected-file=" .. vim.fn.fnameescape(root .. "/" .. path))
        end
        vim.cmd(table.concat(args, " "))
      end)
      return ""
    end
  end,
  opts = function()
    local actions = require("diffview.actions")
    local close = { "n", "q", "<cmd>DiffviewClose<cr>", { desc = "Close Diffview" } }
    return {
      enhanced_diff_hl = true, -- VS Code-like: deleted lines red on left, added green on right
      view = {
        default = { layout = "diff2_horizontal" }, -- old | new, side by side
        file_history = { layout = "diff2_horizontal" },
        merge_tool = { layout = "diff3_mixed", disable_diagnostics = true },
      },
      file_panel = {
        listing_style = "tree",
        win_config = { position = "left", width = 35 },
      },
      hooks = {
        diff_buf_read = function()
          vim.opt_local.wrap = false
        end,
      },
      -- q closes Diffview; stage/commit/push work from both the file list and the diff windows
      keymaps = {
        view = {
          close,
          { "n", "<leader>ga", actions.toggle_stage_entry, { desc = "Stage / unstage this file" } },
          { "n", "<leader>gc", commit, { desc = "Commit" } },
          { "n", "<leader>gp", push, { desc = "Push" } },
          { "n", "<leader>gu", pull, { desc = "Pull" } },
        },
        file_panel = {
          close,
          { "n", "cc", commit, { desc = "Commit" } },
          { "n", "P", push, { desc = "Push" } },
          { "n", "p", pull, { desc = "Pull" } },
          { "n", "<leader>ga", actions.toggle_stage_entry, { desc = "Stage / unstage this file" } },
          { "n", "<leader>gc", commit, { desc = "Commit" } },
          { "n", "<leader>gp", push, { desc = "Push" } },
          { "n", "<leader>gu", pull, { desc = "Pull" } },
        },
        file_history_panel = { close },
      },
    }
  end,
}
