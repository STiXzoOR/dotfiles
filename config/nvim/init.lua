-- Neovim Configuration
-- Using lazy.nvim as the package manager

-- Set leader key before loading lazy
vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

-- Load core configuration
require("config.options")
require("config.keymaps")
require("config.autocmds")

-- Bootstrap and load lazy.nvim
require("config.lazy")
