# Git diff, stage, commit, push & pull (VS Code style)

Side-by-side git diffs in LazyVim using [diffview.nvim](https://github.com/sindrets/diffview.nvim),
plus lazygit themed to look like VS Code.

## Open / close

| Key          | Action                                                   |
|--------------|----------------------------------------------------------|
| `<leader>gv` | Toggle Diffview for all uncommitted changes              |
| `<leader>gV` | File history of the current file (each commit as a diff) |
| `<leader>gm` | Diff your branch against main (PR review)                |
| `<leader>gg` | Open lazygit (full screen)                               |
| `q`          | Close Diffview and return to your code                   |

## Inside Diffview

| Action                         | File list (left) | Diff windows  |
|--------------------------------|------------------|---------------|
| Stage / unstage file           | `-` or `s`       | `<leader>ga`  |
| Stage all / unstage all        | `S` / `U`        |               |
| Discard file changes           | `X`              |               |
| Commit                         | `cc`             | `<leader>gc`  |
| Push                           | `P`              | `<leader>gp`  |
| Pull                           | `p`              | `<leader>gu`  |
| Merge origin/main into branch  | `m`              |               |
| Next / previous file           | `Tab` / `S-Tab`  | `Tab` / `S-Tab` |
| Next / previous change         |                  | `]c` / `[c`   |
| Toggle file list               | `<leader>b`      | `<leader>b`   |
| All keymaps                    | `g?`             | `g?`          |
| Close                          | `q`              | `q`           |

### Sync status (under "Changes (N)" in the file list)

Like VS Code's sync button. Fetches quietly when Diffview opens, then every 3 minutes while it stays
open, and updates after every commit/push/pull.

| Shows                     | Meaning                                   |
|---------------------------|-------------------------------------------|
| `↓2 (p)  main`            | 2 commits on the remote to pull — press `p` |
| `↑1 (P)  main`            | 1 local commit to push — press `P`        |
| `↓2 (p) ↑1 (P)  main`     | Both                                      |
| `✓ in sync  main`         | Nothing to pull or push                   |
| `↑3 publish (P)  feature` | Branch not on the remote yet, 3 commits to send — `P` publishes it |
| `↓2 from origin/main (m)` | (second line, feature branches) main has 2 commits this branch doesn't — `m` merges them in |
| `✓ up to date with origin/main` | (second line) this branch already has everything on main |

`m` fetches main and merges it as `Merge branch 'main' into <your branch>` (never a rebase, so pushed
commits aren't rewritten). Uncommitted changes are set aside and restored. On a conflict, the files show up
in the file list; resolve them, then commit with `cc`. Push the merge with `P` afterwards.

The status comes before the branch name, so a long branch name is cut off at the panel edge, not the status.

Notes:

- **Commit** prompts for a message. If nothing is staged it offers to stage everything first.
- **Push** sets the upstream automatically on a branch's first push (`git push -u origin HEAD`).
- **Pull** runs `git pull --autostash`, so it works with uncommitted changes (they're set aside and
  restored). If it fails with "divergent branches", pick a strategy once:
  `git config --global pull.rebase true`
- Push/pull can't answer username or password prompts. Use SSH keys or a saved HTTPS login.
- The right-hand pane is your real file, so you can edit it directly.
- Both sides scroll together with keys **and** the mouse/trackpad (vertical and sideways), whichever side
  the pointer is over. Mouse sync is a fix in `lua/config/keymaps.lua` (Neovim skips scrollbind for
  wheel scrolls over a non-focused window).
- Inside Diffview only, `<leader>gc` / `<leader>gp` replace LazyVim's usual meanings (git log / GitHub PRs).

## Inside lazygit

| Key      | Action                                                        |
|----------|---------------------------------------------------------------|
| `Ctrl-v` | Open selected file (Files) or commit (Commits) in Diffview    |
| `\|`     | Switch between side-by-side and combined diff views           |
| `+` / `_`| Enlarge / shrink the focused panel                            |

`Ctrl-v` only works when lazygit was opened from Neovim (`<leader>gg`). lazygit stays running
in the background, so `q` in Diffview then `<leader>gg` brings you back where you were.

## Commands

```vim
:DiffviewOpen                     " all uncommitted changes
:DiffviewOpen HEAD~3              " changes since 3 commits ago
:DiffviewOpen main...HEAD         " your branch vs main
:DiffviewOpen <hash>^!            " a single commit
:DiffviewFileHistory %            " history of the current file
:DiffviewFileHistory              " history of the whole repo
:DiffviewRefresh                  " reload the file list
:DiffviewClose
```

## Troubleshooting

- `<leader>gm` says `origin/HEAD` is unknown: run `git remote set-head origin -a` in the repo.

## Where it's configured

| File                                    | What                                                     |
|-----------------------------------------|----------------------------------------------------------|
| `~/.config/nvim/lua/plugins/diffview.lua` | Diffview setup, keymaps, commit/push/pull, lazygit hand-off |
| `~/.config/nvim/lua/plugins/snacks.lua`   | Full-screen lazygit window                               |
| `~/.config/lazygit/config.yml`            | Diff renderers (`\|`), panel width, `Ctrl-v` command     |
| `~/.config/lazygit/delta.gitconfig`       | VS Code Dark+ colours for delta                          |
