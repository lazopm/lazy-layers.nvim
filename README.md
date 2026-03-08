# lazy-layers.nvim

A layer system for modular Neovim configs. Adds dependency resolution and conditional loading on top of [lazy.nvim](https://github.com/folke/lazy.nvim).

## Installation

Bootstrap before `lazy.setup()` in your `init.lua`:

```lua
-- after lazy.nvim bootstrap
local lazy_root = vim.fn.stdpath("data") .. "/lazy"
vim.opt.rtp:prepend(lazy_root .. "/lazy-layers.nvim")

local ok, lazy_layers = pcall(require, "lazy-layers")
local spec = ok and lazy_layers.resolve({
  { import = "layers" },
}) or { { import = "layers.base.plugins" } }

-- let lazy manage updates
table.insert(spec, { "lazopm/lazy-layers.nvim" })

require("lazy").setup({ spec = spec })
```

## Layer spec

Layers are defined using a familiar API modeled after lazy.nvim plugin specs.

### Spec forms

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

### Layer fields

| Field | Type | Description |
|---|---|---|
| `name` | `string` | Layer identity (required for inline, returned by module for others) |
| `dependencies` | `string[]` | Layer names this depends on |
| `cond` | `fun(): boolean` | Whether to activate (default `true`) |
| `init` | `fun()` | Runs at resolve time, before `lazy.setup()` |
| `config` | `fun()` | Runs after all plugins are loaded (`LazyDone`) |
| `plugins` | `table[]` | Inline lazy.nvim plugin specs |

### Import form

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

Plugins go in a sibling module at `lua/layers/work/plugins.lua` (or `lua/layers/work/plugins/`), loaded via lazy.nvim's `import`.

### Git repos and local directories

For `"user/repo"` or `{ dir = "path" }`, the repo/directory must contain a Lua module that returns a layer table (e.g. `lua/<name>/init.lua`). The module is loaded onto the rtp automatically. Git repos are cloned to lazy's install directory on first use.

## How it works

1. **Collect** — gather layers from all spec entries
2. **Evaluate** — check each layer's `cond()`, discard failures
3. **Prune** — iteratively remove layers with unmet dependencies
4. **Sort** — topological sort by `dependencies` (warns on cycles)
5. **Init** — call `init` hooks in dependency order
6. **Build** — return ordered lazy.nvim plugin specs
7. **Config** — `config` hooks fire on `LazyDone`

## Commands

- `:Layers` — print the list of active layers in load order
