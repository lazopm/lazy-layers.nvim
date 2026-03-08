# lazy-layers.nvim
> [!WARNING]
> This plugin was largely vibe-coded and not well tested yet.

A layer system for modular Neovim configs built on [lazy.nvim](https://github.com/folke/lazy.nvim). Organize plugins into dependency-aware, conditionally-loaded layers.

## Why Layers?

One Neovim config, many contexts. Your laptop has a full setup with treesitter, LSP, and a fancy statusline. At work you add project-specific linters and formatters.

Without layers this means `if` statements scattered across dozens of plugin specs. With lazy-layers, each context is a self-contained layer that activates automatically:

```
lua/layers/
├── base/          -- always active: editor essentials
│   ├── init.lua
│   └── plugins/
│       ├── editor.lua
│       ├── lsp.lua
│       └── treesitter.lua
└── work/          -- activates when ~/work exists
    ├── init.lua
    └── plugins/
        ├── formatters.lua
        └── linters.lua
```

```lua
-- lua/layers/base/init.lua
return { name = "base" }

-- lua/layers/work/init.lua
return {
  name = "work",
  dependencies = { "base" },
  cond = function()
    return vim.uv.fs_stat(vim.fn.expand("~/work")) ~= nil
  end,
}
```

Layers that fail their `cond` are skipped entirely — no plugins loaded, no side effects. Layers whose dependencies are missing are pruned automatically. Everything else is resolved in dependency order and handed to lazy.nvim as a flat spec.

## Installation

Bootstrap before `lazy.setup()`:

```lua
local lazy_root = vim.fn.stdpath("data") .. "/lazy"
vim.opt.rtp:prepend(lazy_root .. "/lazy-layers.nvim")

local ok, lazy_layers = pcall(require, "lazy-layers")
local spec = ok
    and lazy_layers.resolve({ { import = "layers" } })
  or { { import = "layers.base.plugins" } }

table.insert(spec, { "lazopm/lazy-layers.nvim" })

require("lazy").setup({ spec = spec })
```

## Layer Spec

Layers use an API modeled after lazy.nvim plugin specs.

### Spec Forms

```lua
require("lazy-layers").resolve({
  -- auto-discover all layers under lua/layers/
  { import = "layers" },

  -- git repo (cloned automatically on first run)
  "user/some-layer",

  -- git repo with overrides
  { "user/some-layer", dependencies = { "base" } },

  -- local directory
  { dir = "~/my-layer" },

  -- inline (everything in one place)
  {
    name = "snippets",
    dependencies = { "base" },
    cond = function() return true end,
    init = function() vim.g.snippets = true end,
    config = function() print("loaded!") end,
    plugins = {
      { "L3MON4D3/LuaSnip" },
    },
  },
})
```

### Layer Fields

| Field          | Type             | Description                                         |
| -------------- | ---------------- | --------------------------------------------------- |
| `name`         | `string`         | Layer identity (required for inline layers)         |
| `dependencies` | `string[]`       | Layer names this layer depends on                   |
| `cond`         | `fun(): boolean` | Whether to activate (default `true`)                |
| `init`         | `fun()`          | Runs at resolve time, before `lazy.setup()`         |
| `config`       | `fun()`          | Runs after all plugins are loaded (`LazyDone`)      |
| `plugins`      | `table[]`        | Inline lazy.nvim plugin specs                       |

### Import Form

`{ import = "layers" }` scans `lua/layers/` for subdirectories. Each must have an `init.lua` that returns a layer table:

```lua
-- lua/layers/work/init.lua
return {
  name = "work",
  dependencies = { "base" },
  cond = function()
    return vim.uv.fs_stat(vim.fn.expand("~/work")) ~= nil
  end,
}
```

Plugins go in a sibling module at `lua/layers/<name>/plugins.lua` (or `lua/layers/<name>/plugins/`), loaded via lazy.nvim's `import`.

### Git Repos and Local Directories

For `"user/repo"` or `{ dir = "path" }`, the target must contain a Lua module returning a layer table (e.g. `lua/<name>/init.lua`). The module is added to the rtp automatically. Git repos are cloned to lazy's install directory on first use.

## How It Works

1. **Collect** — gather layers from all spec entries
2. **Evaluate** — check each layer's `cond`; discard inactive layers
3. **Prune** — iteratively remove layers with unmet dependencies
4. **Sort** — topological sort by `dependencies` (warns on cycles)
5. **Init** — call `init` hooks in dependency order
6. **Build** — return ordered lazy.nvim plugin specs
7. **Config** — call `config` hooks on `LazyDone`

## Commands

- `:Layers` — print the list of active layers in load order
