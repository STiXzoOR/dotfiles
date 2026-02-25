-- LSP Configuration
return {
  -- Mason for managing LSP servers
  {
    "williamboman/mason.nvim",
    cmd = "Mason",
    keys = { { "<leader>cm", "<cmd>Mason<cr>", desc = "Mason" } },
    build = ":MasonUpdate",
    opts = {
      ensure_installed = {
        "stylua",
        "shfmt",
        "prettier",
        "eslint_d",
      },
    },
    config = function(_, opts)
      require("mason").setup(opts)
      local mr = require("mason-registry")
      local function ensure_installed()
        for _, tool in ipairs(opts.ensure_installed) do
          local p = mr.get_package(tool)
          if not p:is_installed() then
            p:install()
          end
        end
      end
      if mr.refresh then
        mr.refresh(ensure_installed)
      else
        ensure_installed()
      end
    end,
  },

  -- LSP configuration
  {
    "neovim/nvim-lspconfig",
    event = { "BufReadPre", "BufNewFile" },
    dependencies = {
      "mason.nvim",
      "williamboman/mason-lspconfig.nvim",
      { "j-hui/fidget.nvim", opts = {} },
    },
    opts = {
      diagnostics = {
        underline = true,
        update_in_insert = false,
        virtual_text = {
          spacing = 4,
          source = "if_many",
          prefix = "●",
        },
        severity_sort = true,
      },
      servers = {
        lua_ls = {
          settings = {
            Lua = {
              workspace = {
                checkThirdParty = false,
              },
              completion = {
                callSnippet = "Replace",
              },
              diagnostics = {
                globals = { "vim" },
              },
            },
          },
        },
        ts_ls = {},
        pyright = {},
        rust_analyzer = {},
        gopls = {},
        bashls = {},
        jsonls = {},
        yamlls = {},
        html = {},
        cssls = {},
      },
    },
    config = function(_, opts)
      -- Diagnostics configuration
      vim.diagnostic.config(opts.diagnostics)

      -- LSP keymaps
      vim.api.nvim_create_autocmd("LspAttach", {
        group = vim.api.nvim_create_augroup("UserLspConfig", {}),
        callback = function(ev)
          local buffer = ev.buf
          local client = vim.lsp.get_clients({ id = ev.data.client_id })[1]

          local function map(mode, lhs, rhs, desc)
            vim.keymap.set(mode, lhs, rhs, { buffer = buffer, desc = desc })
          end

          -- Go to definition
          map("n", "gd", vim.lsp.buf.definition, "Go to definition")
          map("n", "gr", vim.lsp.buf.references, "Go to references")
          map("n", "gD", vim.lsp.buf.declaration, "Go to declaration")
          map("n", "gI", vim.lsp.buf.implementation, "Go to implementation")
          map("n", "gy", vim.lsp.buf.type_definition, "Go to type definition")

          -- Hover and signature help
          map("n", "K", vim.lsp.buf.hover, "Hover documentation")
          map("n", "gK", vim.lsp.buf.signature_help, "Signature help")
          map("i", "<C-k>", vim.lsp.buf.signature_help, "Signature help")

          -- Actions
          map("n", "<leader>ca", vim.lsp.buf.code_action, "Code action")
          map("n", "<leader>cr", vim.lsp.buf.rename, "Rename")
          map("n", "<leader>cf", function()
            vim.lsp.buf.format({ async = true })
          end, "Format document")

          -- Workspace
          map("n", "<leader>wa", vim.lsp.buf.add_workspace_folder, "Add workspace folder")
          map("n", "<leader>wr", vim.lsp.buf.remove_workspace_folder, "Remove workspace folder")
          map("n", "<leader>wl", function()
            print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
          end, "List workspace folders")

          -- Inlay hints (Neovim 0.10+)
          if client and client.server_capabilities.inlayHintProvider and vim.lsp.inlay_hint then
            map("n", "<leader>uh", function()
              vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled())
            end, "Toggle inlay hints")
          end
        end,
      })

      -- Setup mason-lspconfig
      require("mason-lspconfig").setup({
        ensure_installed = vim.tbl_keys(opts.servers),
        automatic_installation = true,
      })

      -- Setup each server
      local capabilities = vim.lsp.protocol.make_client_capabilities()
      local has_cmp, cmp_nvim_lsp = pcall(require, "cmp_nvim_lsp")
      if has_cmp then
        capabilities = vim.tbl_deep_extend("force", capabilities, cmp_nvim_lsp.default_capabilities())
      end

      require("mason-lspconfig").setup_handlers({
        function(server_name)
          local server_opts = opts.servers[server_name] or {}
          server_opts.capabilities = vim.tbl_deep_extend("force", {}, capabilities, server_opts.capabilities or {})
          require("lspconfig")[server_name].setup(server_opts)
        end,
      })
    end,
  },

  -- Autocompletion
  {
    "hrsh7th/nvim-cmp",
    version = false,
    event = "InsertEnter",
    dependencies = {
      "hrsh7th/cmp-nvim-lsp",
      "hrsh7th/cmp-buffer",
      "hrsh7th/cmp-path",
      "hrsh7th/cmp-cmdline",
      {
        "L3MON4D3/LuaSnip",
        version = "v2.*",
        build = "make install_jsregexp",
        dependencies = {
          "rafamadriz/friendly-snippets",
          config = function()
            require("luasnip.loaders.from_vscode").lazy_load()
          end,
        },
      },
      "saadparwaiz1/cmp_luasnip",
    },
    opts = function()
      local cmp = require("cmp")
      local luasnip = require("luasnip")

      return {
        completion = {
          completeopt = "menu,menuone,noinsert",
        },
        snippet = {
          expand = function(args)
            luasnip.lsp_expand(args.body)
          end,
        },
        mapping = cmp.mapping.preset.insert({
          ["<C-n>"] = cmp.mapping.select_next_item({ behavior = cmp.SelectBehavior.Insert }),
          ["<C-p>"] = cmp.mapping.select_prev_item({ behavior = cmp.SelectBehavior.Insert }),
          ["<C-b>"] = cmp.mapping.scroll_docs(-4),
          ["<C-f>"] = cmp.mapping.scroll_docs(4),
          ["<C-Space>"] = cmp.mapping.complete(),
          ["<C-e>"] = cmp.mapping.abort(),
          ["<CR>"] = cmp.mapping.confirm({ select = true }),
          ["<S-CR>"] = cmp.mapping.confirm({
            behavior = cmp.ConfirmBehavior.Replace,
            select = true,
          }),
          ["<Tab>"] = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_next_item()
            elseif luasnip.expand_or_jumpable() then
              luasnip.expand_or_jump()
            else
              fallback()
            end
          end, { "i", "s" }),
          ["<S-Tab>"] = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_prev_item()
            elseif luasnip.jumpable(-1) then
              luasnip.jump(-1)
            else
              fallback()
            end
          end, { "i", "s" }),
        }),
        sources = cmp.config.sources({
          { name = "nvim_lsp" },
          { name = "luasnip" },
          { name = "path" },
        }, {
          { name = "buffer" },
        }),
        formatting = {
          format = function(_, item)
            local icons = {
              Array = " ",
              Boolean = "󰨙 ",
              Class = " ",
              Codeium = "󰘦 ",
              Color = " ",
              Control = " ",
              Collapsed = " ",
              Constant = "󰏿 ",
              Constructor = " ",
              Copilot = " ",
              Enum = " ",
              EnumMember = " ",
              Event = " ",
              Field = " ",
              File = " ",
              Folder = " ",
              Function = "󰊕 ",
              Interface = " ",
              Key = " ",
              Keyword = " ",
              Method = "󰊕 ",
              Module = " ",
              Namespace = "󰦮 ",
              Null = " ",
              Number = "󰎠 ",
              Object = " ",
              Operator = " ",
              Package = " ",
              Property = " ",
              Reference = " ",
              Snippet = " ",
              String = " ",
              Struct = "󰆼 ",
              TabNine = "󰏚 ",
              Text = " ",
              TypeParameter = " ",
              Unit = " ",
              Value = " ",
              Variable = "󰀫 ",
            }
            if icons[item.kind] then
              item.kind = icons[item.kind] .. item.kind
            end
            return item
          end,
        },
        experimental = {
          ghost_text = {
            hl_group = "CmpGhostText",
          },
        },
      }
    end,
    config = function(_, opts)
      local cmp = require("cmp")
      cmp.setup(opts)

      -- Cmdline completion
      cmp.setup.cmdline("/", {
        mapping = cmp.mapping.preset.cmdline(),
        sources = {
          { name = "buffer" },
        },
      })

      cmp.setup.cmdline(":", {
        mapping = cmp.mapping.preset.cmdline(),
        sources = cmp.config.sources({
          { name = "path" },
        }, {
          { name = "cmdline" },
        }),
      })
    end,
  },
}
