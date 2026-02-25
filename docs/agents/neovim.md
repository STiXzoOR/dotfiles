# Neovim Configuration

Uses **lazy.nvim** as package manager. Config lives in `config/nvim/`.

## Structure

- `init.lua` — entry point
- `lua/config/` — options, keymaps, autocmds, lazy.nvim bootstrap
- `lua/plugins/` — plugin specs: `colorscheme.lua`, `editor.lua`, `git.lua`, `lsp.lua`, `treesitter.lua`, `ui.lua`

## Key Bindings (Leader = Space)

| Binding      | Action               |
| ------------ | -------------------- |
| `<leader>ff` | Find files           |
| `<leader>fg` | Live grep            |
| `<leader>ee` | Toggle file explorer |
| `<leader>gg` | LazyGit              |
| `<leader>ca` | Code actions         |
| `<leader>cr` | Rename symbol        |

## Themes

Catppuccin, Nord, TokyoNight available in `lua/plugins/colorscheme.lua`.
