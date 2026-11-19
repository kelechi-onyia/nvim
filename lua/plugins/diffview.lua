-- VS Code-style side-by-side git diff

-- git helpers so you can commit and push without leaving Diffview
local function repo_root(view)
  view = view or require("diffview.lib").get_current_view()
  return view and view.adapter.ctx.toplevel or vim.fn.getcwd()
end

local function git(root, args, on_ok, on_err)
  vim.system(
    vim.list_extend({ "git" }, args),
    { text = true, cwd = root, env = { GIT_TERMINAL_PROMPT = "0" } },
    function(r)
      vim.schedule(function()
        if r.code ~= 0 then
          local err = vim.trim(r.stderr ~= "" and r.stderr or r.stdout)
          vim.notify(err, vim.log.levels.ERROR, { title = "git " .. args[1] })
          if on_err then
            on_err(r)
          end
        elseif on_ok then
          on_ok(r)
        end
      end)
    end
  )
end

-- the remote's default branch, e.g. "origin/main" (from origin/HEAD, falling back to origin/main)
local function base_branch(root, cb)
  vim.system({ "git", "symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD" }, { text = true, cwd = root }, function(r)
    local base = vim.trim(r.stdout or "")
    cb(r.code == 0 and base ~= "" and base or "origin/main")
  end)
end

-- VS Code-style sync status (↓ to pull, ↑ to push) as lines under the file panel's "Changes (N)"
local sync_lines = {}
local sync_ns = vim.api.nvim_create_namespace("diffview_sync_status")

local function render_sync()
  for _, view in ipairs(require("diffview.lib").views) do
    local buf = view.panel and view.panel.bufid
    if buf and vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_clear_namespace(buf, sync_ns, 0, -1)
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local row
      for i, line in ipairs(lines) do
        -- "Changes" is hidden when it's empty and there are staged files
        if line:match("^Changes %(%d+%)") or (not row and line:match("^Staged changes %(%d+%)")) then
          row = i - 1
        end
      end
      if row and #sync_lines > 0 then
        vim.api.nvim_buf_set_extmark(buf, sync_ns, row, 0, { virt_lines = sync_lines })
      end
    end
  end
end

-- status first, branch name last: the panel is narrow, so a long branch name gets cut, not the status.
-- A second line shows commits on the default branch (e.g. origin/main) this branch doesn't have yet.
local function format_sync(status, unpublished, base, base_behind)
  local head = status:match("# branch%.head (%S+)") or "?"
  local chunks = { { "  " } }
  if not status:match("# branch%.upstream ") then
    local n = (unpublished or 0) > 0 and unpublished or ""
    table.insert(chunks, { "↑" .. n .. " publish (P)", "DiagnosticInfo" })
  else
    local ahead, behind = status:match("# branch%.ab %+(%d+) %-(%d+)")
    ahead, behind = tonumber(ahead) or 0, tonumber(behind) or 0
    if ahead == 0 and behind == 0 then
      table.insert(chunks, { "✓ in sync", "Comment" })
    end
    if behind > 0 then
      table.insert(chunks, { "↓" .. behind .. " (p)", "DiagnosticWarn" })
    end
    if behind > 0 and ahead > 0 then
      table.insert(chunks, { " " })
    end
    if ahead > 0 then
      table.insert(chunks, { "↑" .. ahead .. " (P)", "DiagnosticOk" })
    end
  end
  table.insert(chunks, { "  " .. head, "Comment" })
  local lines = { chunks }
  if base_behind == 0 then
    table.insert(lines, { { "  " }, { "✓ up to date with " .. base, "Comment" } })
  elseif base_behind then
    table.insert(lines, { { "  " }, { "↓" .. base_behind .. " from " .. base .. " (m)", "DiagnosticWarn" } })
  end
  return lines
end

local function update_sync(root, fetch)
  local function show(lines)
    vim.schedule(function()
      sync_lines = lines
      render_sync()
    end)
  end
  local function run(args, cb)
    vim.system(vim.list_extend({ "git" }, args), { text = true, cwd = root }, cb)
  end
  local function count()
    run({ "status", "--porcelain=v2", "--branch", "--untracked-files=no" }, function(r)
      if r.code ~= 0 then
        return show({})
      end
      local head = r.stdout:match("# branch%.head (%S+)")
      local unpublished
      local function with_base()
        base_branch(root, function(base)
          -- on the default branch itself, the ↓ above already covers it
          if base == "origin/" .. head then
            return show(format_sync(r.stdout, unpublished))
          end
          run({ "rev-list", "--count", "HEAD.." .. base }, function(c)
            -- no line at all if the base branch doesn't exist (c.code ~= 0)
            show(format_sync(r.stdout, unpublished, base, c.code == 0 and tonumber(vim.trim(c.stdout)) or nil))
          end)
        end)
      end
      if r.stdout:match("# branch%.upstream ") then
        return with_base()
      end
      -- branch not pushed yet: count the commits no remote has
      run({ "rev-list", "--count", "HEAD", "--not", "--remotes" }, function(c)
        unpublished = tonumber(vim.trim(c.stdout or ""))
        with_base()
      end)
    end)
  end
  count()
  if fetch then
    -- quiet fetch so "↓ to pull" reflects the remote, then recount
    vim.system({ "git", "fetch", "--quiet" }, { cwd = root, env = { GIT_TERMINAL_PROMPT = "0" } }, function()
      vim.schedule(count)
    end)
  end
end

-- background fetch every 3 minutes while Diffview is open (like VS Code's autofetch)
local AUTOFETCH_MS = 3 * 60 * 1000
local fetch_timer

local function start_autofetch()
  if fetch_timer then
    return
  end
  fetch_timer = vim.uv.new_timer()
  fetch_timer:start(AUTOFETCH_MS, AUTOFETCH_MS, vim.schedule_wrap(function()
    local views = require("diffview.lib").views
    if #views == 0 then
      fetch_timer:stop()
      fetch_timer:close()
      fetch_timer = nil
      return
    end
    local seen = {}
    for _, view in ipairs(views) do
      local root = repo_root(view)
      if not seen[root] then
        seen[root] = true
        update_sync(root, true)
      end
    end
  end))
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
        update_sync(root)
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
        update_sync(root)
      end)
    end)
  end)
end

-- args is a pull or merge; --autostash lets it run with uncommitted changes (they're restored afterwards)
local function run_pull(root, args)
  git(root, args, function(r)
    -- first and last line, e.g. "Updating a..b" + "2 files changed, ..."
    local lines = vim.tbl_filter(function(l)
      return not l:match("autostash")
    end, vim.split(vim.trim(r.stdout), "\n"))
    lines = #lines > 0 and lines or { "Pulled" }
    local msg = #lines > 1 and (lines[1] .. "\n" .. vim.trim(lines[#lines])) or lines[1]
    vim.notify(msg, vim.log.levels.INFO, { title = "git " .. args[1] })
    vim.cmd("DiffviewRefresh")
    update_sync(root)
  end, function()
    -- e.g. merge conflicts: show them in the file list
    vim.cmd("DiffviewRefresh")
    update_sync(root)
  end)
end

local function pull()
  vim.notify("Pulling…", vim.log.levels.INFO, { title = "git pull" })
  run_pull(repo_root(), { "pull", "--autostash" })
end

-- bring the default branch (e.g. origin/main) into this branch, as a merge like
-- "Merge branch 'main' into feature/..." (never a rebase, so pushed commits aren't rewritten)
local function pull_base()
  local root = repo_root()
  base_branch(root, function(base)
    local remote, branch = base:match("^([^/]+)/(.+)$")
    vim.schedule(function()
      vim.notify("Merging " .. base .. "…", vim.log.levels.INFO, { title = "git merge" })
      git(root, { "fetch", "--quiet", remote, branch }, function()
        git(root, { "branch", "--show-current" }, function(r)
          local msg = ("Merge branch '%s' into %s"):format(branch, vim.trim(r.stdout))
          run_pull(root, { "merge", "--autostash", "--no-edit", "-m", msg, base })
        end)
      end)
    end)
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
    -- Diffview rewrites the file panel on every redraw, which drops the sync line, so add it back
    local FilePanel = require("diffview.scene.views.diff.file_panel").FilePanel
    if not FilePanel.sync_status_patched then
      local redraw = FilePanel.redraw
      FilePanel.redraw = function(...)
        redraw(...)
        render_sync()
      end
      FilePanel.sync_status_patched = true
    end
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
        -- blank winbar: the global one (filename) would show the panel's internal buffer name
        -- (" ", not "": an empty window value falls back to the global one)
        win_config = { position = "left", width = 35, win_opts = { winbar = " " } },
      },
      hooks = {
        diff_buf_read = function()
          vim.opt_local.wrap = false
        end,
        view_opened = function(view)
          update_sync(repo_root(view), true)
          start_autofetch()
        end,
        view_enter = function(view)
          update_sync(repo_root(view))
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
          { "n", "m", pull_base, { desc = "Merge origin/main into this branch" } },
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
