-- Autocommands

local augroup = vim.api.nvim_create_augroup
local autocmd = vim.api.nvim_create_autocmd

-- General Settings
local general = augroup("General", { clear = true })

-- Highlight on yank
autocmd("TextYankPost", {
  group = general,
  callback = function()
    vim.highlight.on_yank({ higroup = "IncSearch", timeout = 200 })
  end,
  desc = "Highlight text on yank",
})

-- Remove whitespace on save
autocmd("BufWritePre", {
  group = general,
  pattern = "*",
  command = [[%s/\s\+$//e]],
  desc = "Remove trailing whitespace on save",
})

-- Resize splits when window is resized
autocmd("VimResized", {
  group = general,
  callback = function()
    vim.cmd("tabdo wincmd =")
  end,
  desc = "Resize splits on window resize",
})

-- Go to last location when opening a buffer
autocmd("BufReadPost", {
  group = general,
  callback = function()
    local mark = vim.api.nvim_buf_get_mark(0, '"')
    local lcount = vim.api.nvim_buf_line_count(0)
    if mark[1] > 0 and mark[1] <= lcount then
      pcall(vim.api.nvim_win_set_cursor, 0, mark)
    end
  end,
  desc = "Go to last location when opening a buffer",
})

-- Close some filetypes with <q>
autocmd("FileType", {
  group = general,
  pattern = {
    "help",
    "lspinfo",
    "man",
    "notify",
    "qf",
    "query",
    "spectre_panel",
    "startuptime",
    "checkhealth",
  },
  callback = function(event)
    vim.bo[event.buf].buflisted = false
    vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = event.buf, silent = true })
  end,
  desc = "Close certain filetypes with q",
})

-- Check if file changed outside of vim
autocmd({ "FocusGained", "TermClose", "TermLeave" }, {
  group = general,
  command = "checktime",
  desc = "Check if file changed outside of vim",
})

-- Auto create directories when saving a file
autocmd("BufWritePre", {
  group = general,
  callback = function(event)
    if event.match:match("^%w%w+://") then
      return
    end
    local file = vim.uv.fs_realpath(event.match) or event.match
    vim.fn.mkdir(vim.fn.fnamemodify(file, ":p:h"), "p")
  end,
  desc = "Auto create directories when saving a file",
})

-- Filetype-specific settings
local filetypes = augroup("Filetypes", { clear = true })

-- Set indentation for specific filetypes
autocmd("FileType", {
  group = filetypes,
  pattern = { "lua", "javascript", "typescript", "json", "yaml", "html", "css" },
  callback = function()
    vim.opt_local.tabstop = 2
    vim.opt_local.shiftwidth = 2
  end,
  desc = "Set 2-space indentation for certain filetypes",
})

autocmd("FileType", {
  group = filetypes,
  pattern = { "python", "rust", "go" },
  callback = function()
    vim.opt_local.tabstop = 4
    vim.opt_local.shiftwidth = 4
  end,
  desc = "Set 4-space indentation for certain filetypes",
})

-- Enable spell checking for certain filetypes
autocmd("FileType", {
  group = filetypes,
  pattern = { "markdown", "gitcommit", "text" },
  callback = function()
    vim.opt_local.spell = true
    vim.opt_local.wrap = true
  end,
  desc = "Enable spell checking for markdown and git commits",
})

-- Disable line numbers in terminal
autocmd("TermOpen", {
  group = general,
  callback = function()
    vim.opt_local.number = false
    vim.opt_local.relativenumber = false
  end,
  desc = "Disable line numbers in terminal",
})
