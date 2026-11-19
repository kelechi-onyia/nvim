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
  vim.system(
    { "git", "symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD" },
    { text = true, cwd = root },
    function(r)
      local base = vim.trim(r.stdout or "")
      cb(r.code == 0 and base ~= "" and base or "origin/main")
    end
  )
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

-- Colour ONLY the "Changes (N)" section title orange. In the source both the
-- "Changes" and "Staged changes" titles share DiffviewFilePanelTitle, so the
-- override is matched to the literal "Changes (N)" line and painted with a
-- per-line extmark (re-applied on redraw, which Diffview wipes highlights on).
local section_ns = vim.api.nvim_create_namespace("diffview_section_colors")

local function setup_section_hl()
  vim.api.nvim_set_hl(0, "DiffviewUnstagedText", { fg = "#f5a97f" }) -- catppuccin peach / orange

  -- sync-line palette (catppuccin macchiato): arrows bold so they pop, key
  -- hints dimmed, so push/pull reads at a glance.
  vim.api.nvim_set_hl(0, "DiffviewPush", { fg = "#a6da95", bold = true }) -- green: ahead, ready to push
  vim.api.nvim_set_hl(0, "DiffviewPull", { fg = "#8aadf4", bold = true }) -- blue: behind, pull
  vim.api.nvim_set_hl(0, "DiffviewPublish", { fg = "#c6a0f6", bold = true }) -- mauve: unpublished branch
  vim.api.nvim_set_hl(0, "DiffviewSynced", { fg = "#8bd5ca" }) -- teal: in sync / up to date
  vim.api.nvim_set_hl(0, "DiffviewSyncHint", { fg = "#6e738d", italic = true }) -- overlay0: dim (P)/(p)/(m)
  vim.api.nvim_set_hl(0, "DiffviewSyncBranch", { fg = "#b8c0e0", bold = true }) -- subtext1: branch name
end

local function render_section_colors()
  for _, view in ipairs(require("diffview.lib").views) do
    local buf = view.panel and view.panel.bufid
    if buf and vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_clear_namespace(buf, section_ns, 0, -1)
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      for i, line in ipairs(lines) do
        if line:match("^Changes %(%d+%)") then
          local title = line:match("^(.-) %(%d+%)")
          vim.api.nvim_buf_set_extmark(buf, section_ns, i - 1, 0, {
            end_col = #title,
            hl_group = "DiffviewUnstagedText",
            -- must exceed nvim_buf_add_highlight's default priority (4096) that
            -- Diffview uses for DiffviewFilePanelTitle, or our colour is overridden
            priority = 5000,
          })
        end
      end
    end
  end
end

setup_section_hl()
-- re-link the groups after a colorscheme change clears them
vim.api.nvim_create_autocmd("ColorScheme", { callback = setup_section_hl })

-- Side-by-side preview of ALL of a folder's changes: when the cursor lands on a
-- folder row, show every changed file under it as old | new in two floating
-- windows running Vim's native diff. Files are stacked with a header per file.
local folder_preview = {}

local function close_folder_preview()
  -- invalidate any in-flight async render for this preview
  folder_preview.seq = (folder_preview.seq or 0) + 1
  for _, key in ipairs({ "owin", "nwin" }) do
    local win = folder_preview[key]
    if win and vim.api.nvim_win_is_valid(win) then
      pcall(vim.api.nvim_win_close, win, true)
    end
    folder_preview[key] = nil
  end
  -- restore diff mode on the Diffview panes we suspended
  if folder_preview.suspended then
    for win in pairs(folder_preview.suspended) do
      if vim.api.nvim_win_is_valid(win) then
        pcall(vim.api.nvim_set_option_value, "diff", true, { win = win })
      end
    end
    folder_preview.suspended = nil
  end
  folder_preview.path = nil
end

-- Collect the two sides (old / new) for every changed file under the folder.
-- staged: HEAD (old) vs index (new); working: index (old) vs worktree (new).
local function build_folder_sides(view, dir, cb)
  local root = repo_root(view)
  local files = {}
  for _, f in view.files:iter() do
    if f.kind == dir.kind and (f.path == dir.path or vim.startswith(f.path, dir.path .. "/")) then
      files[#files + 1] = f
    end
  end
  table.sort(files, function(a, b)
    return a.path < b.path
  end)
  if #files == 0 then
    local msg = { "No changes in " .. dir.path }
    return cb(msg, msg)
  end

  local results = {}
  local pending = #files
  local function finish()
    local old_lines, new_lines = {}, {}
    for i, f in ipairs(files) do
      local header = "══ " .. f.path .. " ══"
      local function append(dst, content)
        dst[#dst + 1] = header
        for _, l in ipairs(vim.split(content or "", "\n", { plain = true })) do
          dst[#dst + 1] = l
        end
        dst[#dst + 1] = ""
      end
      append(old_lines, results[i].old)
      append(new_lines, results[i].new)
    end
    cb(old_lines, new_lines)
  end

  for i, f in ipairs(files) do
    results[i] = {}
    local got = 0
    local function one()
      got = got + 1
      if got == 2 then
        pending = pending - 1
        if pending == 0 then
          vim.schedule(finish)
        end
      end
    end
    -- old side (always a git object)
    local old_ref = (dir.kind == "staged" and "HEAD:" or ":") .. f.path
    vim.system({ "git", "show", old_ref }, { text = true, cwd = root }, function(r)
      results[i].old = r.code == 0 and r.stdout or ""
      one()
    end)
    -- new side: staged -> index object; working -> the worktree file on disk
    if dir.kind == "staged" then
      vim.system({ "git", "show", ":" .. f.path }, { text = true, cwd = root }, function(r)
        results[i].new = r.code == 0 and r.stdout or ""
        one()
      end)
    else
      local fd = io.open(root .. "/" .. f.path, "r")
      if fd then
        results[i].new = fd:read("*a")
        fd:close()
      else
        results[i].new = "" -- deleted in the worktree
      end
      one()
    end
  end
end

local function show_folder_preview(view, dir)
  if not (dir and dir.path) then
    return close_folder_preview()
  end
  folder_preview.seq = (folder_preview.seq or 0) + 1
  local myseq = folder_preview.seq
  build_folder_sides(view, dir, function(old_lines, new_lines)
    local panel = view.panel
    -- bail if a newer navigation superseded us, or focus left the panel
    if folder_preview.seq ~= myseq then
      return
    end
    if not (panel and panel.winid and vim.api.nvim_win_is_valid(panel.winid) and panel:is_focused()) then
      return
    end

    local function fill(key, lines)
      local buf = folder_preview[key]
      if not (buf and vim.api.nvim_buf_is_valid(buf)) then
        buf = vim.api.nvim_create_buf(false, true)
        vim.bo[buf].bufhidden = "hide"
        folder_preview[key] = buf
      end
      vim.bo[buf].modifiable = true
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      vim.bo[buf].modifiable = false
      return buf
    end
    local obuf = fill("obuf", old_lines)
    local nbuf = fill("nbuf", new_lines)

    -- two floats filling the main diff area, to the right of the file panel
    local col = vim.api.nvim_win_get_width(panel.winid) + 1
    local total = vim.o.columns - col - 1
    local wl = math.max(10, math.floor((total - 1) / 2))
    local wr = math.max(10, total - 1 - wl)
    local height = math.max(5, vim.o.lines - 4)
    local function cfg(c, w, title)
      return {
        relative = "editor",
        row = 1,
        col = c,
        width = w,
        height = height,
        style = "minimal",
        border = "rounded",
        title = title,
        focusable = false,
        noautocmd = true,
      }
    end

    local function place(win_key, buf, c, w, title)
      local win = folder_preview[win_key]
      if win and vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_set_buf(win, buf)
        vim.api.nvim_win_set_config(win, cfg(c, w, title))
      else
        folder_preview[win_key] = vim.api.nvim_open_win(buf, false, cfg(c, w, title))
      end
      return folder_preview[win_key]
    end
    local owin = place("owin", obuf, col, wl, " old ")
    local nwin = place("nwin", nbuf, col + wl + 1, wr, " " .. dir.path .. " (new) ")

    -- Vim groups ALL diff windows in a tabpage together, so suspend diff on any
    -- other diff windows (the Diffview panes, hidden behind our floats) to keep
    -- our two floats as their own isolated diff group. Restored on close.
    folder_preview.suspended = folder_preview.suspended or {}
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if win ~= owin and win ~= nwin and vim.api.nvim_win_is_valid(win) then
        if vim.api.nvim_get_option_value("diff", { win = win }) then
          vim.api.nvim_set_option_value("diff", false, { win = win })
          folder_preview.suspended[win] = true
        end
      end
    end

    -- turn on diff mode in both floats so changes are highlighted
    for _, win in ipairs({ owin, nwin }) do
      vim.api.nvim_win_call(win, function()
        vim.cmd("diffthis")
        vim.wo[win].wrap = false
        vim.wo[win].foldlevel = 99
      end)
    end
    folder_preview.path = dir.path
  end)
end

-- status first, branch name last: the panel is narrow, so a long branch name gets cut, not the status.
-- A second line shows commits on the default branch (e.g. origin/main) this branch doesn't have yet.
local function format_sync(status, unpublished, base, base_behind)
  local head = status:match("# branch%.head (%S+)") or "?"
  local chunks = { { "  " } }
  if not status:match("# branch%.upstream ") then
    local n = (unpublished or 0) > 0 and unpublished or ""
    table.insert(chunks, { "↑" .. n .. " publish ", "DiffviewPublish" })
    table.insert(chunks, { "(P)", "DiffviewSyncHint" })
  else
    local ahead, behind = status:match("# branch%.ab %+(%d+) %-(%d+)")
    ahead, behind = tonumber(ahead) or 0, tonumber(behind) or 0
    if ahead == 0 and behind == 0 then
      table.insert(chunks, { "✓ in sync", "DiffviewSynced" })
    end
    if behind > 0 then
      table.insert(chunks, { "↓" .. behind .. " ", "DiffviewPull" })
      table.insert(chunks, { "(p)", "DiffviewSyncHint" })
    end
    if behind > 0 and ahead > 0 then
      table.insert(chunks, { "  " })
    end
    if ahead > 0 then
      table.insert(chunks, { "↑" .. ahead .. " ", "DiffviewPush" })
      table.insert(chunks, { "(P)", "DiffviewSyncHint" })
    end
  end
  table.insert(chunks, { "  " .. head, "DiffviewSyncBranch" })
  local lines = { chunks }
  if base_behind == 0 then
    table.insert(lines, { { "  " }, { "✓ up to date with " .. base, "DiffviewSynced" } })
  elseif base_behind then
    table.insert(lines, {
      { "  " },
      { "↓" .. base_behind .. " from " .. base .. " ", "DiffviewPull" },
      { "(m)", "DiffviewSyncHint" },
    })
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
  fetch_timer:start(
    AUTOFETCH_MS,
    AUTOFETCH_MS,
    vim.schedule_wrap(function()
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
    end)
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
    -- Move the cursor one line in the file panel (landing on folder rows too, so
    -- they can still be folded), and open a file's diff only when the cursor lands
    -- on an actual file row — unlike <tab>, which skips folders entirely.
    local function move_cursor(dir)
      return function()
        local view = require("diffview.lib").get_current_view()
        local panel = view and view.panel
        if not panel or not panel.winid then
          return
        end
        vim.cmd("normal! " .. (dir > 0 and "j" or "k"))
        local line = vim.api.nvim_win_get_cursor(panel.winid)[1]
        local comp = panel.components.comp:get_comp_on_line(line)
        if comp and comp.name == "file" and comp.context then
          close_folder_preview()
          view:set_file(comp.context, false, true) -- open, keep focus in panel, highlight
        elseif comp and comp.name == "dir_name" then
          -- cursor on a folder: preview all of its changes
          show_folder_preview(view, comp.parent and comp.parent.context)
        else
          close_folder_preview()
        end
      end
    end
    -- Diffview rewrites the file panel on every redraw, which drops the sync line, so add it back
    local FilePanel = require("diffview.scene.views.diff.file_panel").FilePanel
    if not FilePanel.sync_status_patched then
      local redraw = FilePanel.redraw
      FilePanel.redraw = function(...)
        redraw(...)
        render_sync()
        render_section_colors()
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
        view_leave = function()
          close_folder_preview()
        end,
        view_closed = function()
          close_folder_preview()
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
          -- arrow keys move line-by-line (folders included) and open a file's diff
          -- when the cursor lands on one
          { "n", "<down>", move_cursor(1), { desc = "Next row (open file diff)" } },
          { "n", "<up>", move_cursor(-1), { desc = "Previous row (open file diff)" } },
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
