local M = {}

--- Clone a GitHub repo to lazy's install directory if not already present.
---@param repo string  "user/repo" format
---@return string? install_path
---@return string? mod_name
local function ensure_repo(repo)
	local name = repo:match(".+/(.+)$")
	if not name then
		return nil, nil
	end

	local install_path = vim.fn.stdpath("data") .. "/lazy/" .. name
	if not vim.uv.fs_stat(install_path) then
		local url = "https://github.com/" .. repo .. ".git"
		vim.fn.system({ "git", "clone", "--filter=blob:none", url, install_path })
		if vim.v.shell_error ~= 0 then
			vim.notify("lazy-layers: failed to clone " .. repo, vim.log.levels.ERROR)
			return nil, nil
		end
	end

	return install_path, name
end

--- Load a layer module from an external path and merge overrides.
---@param install_path string
---@param mod_name string
---@param overrides? table
---@return table? layer
local function load_external(install_path, mod_name, overrides)
	vim.opt.rtp:prepend(install_path)
	local ok, layer = pcall(require, mod_name)
	if not ok or type(layer) ~= "table" then
		return nil
	end
	if not layer.name then
		layer.name = mod_name
	end
	layer._import_path = mod_name
	if overrides then
		for k, v in pairs(overrides) do
			layer[k] = v
		end
	end
	return layer
end

--- Extract string-keyed override fields from a spec table.
---@param spec table
---@param exclude string[]  Keys to skip
---@return table? overrides
local function extract_overrides(spec, exclude)
	local skip = {}
	for _, k in ipairs(exclude) do
		skip[k] = true
	end
	local out = {}
	for k, v in pairs(spec) do
		if type(k) == "string" and not skip[k] then
			out[k] = v
		end
	end
	return next(out) and out or nil
end

--- Resolve layer specs into an ordered list of lazy.nvim plugin specs.
---
--- Each entry in `specs` can be:
---   "user/repo"                              — git repo (shorthand)
---   { "user/repo", ... }                     — git repo with overrides
---   { dir = "path", ... }                    — local directory
---   { import = "path" }                      — auto-discover layers under lua/<path>/
---   { name = "...", plugins = {...}, ... }    — inline layer
---
---@param specs table[]
---@return table[] lazy_specs  Ordered lazy.nvim plugin specs.
function M.resolve(specs)
	-- 1. Collect all layers
	local candidates = {}

	for _, spec in ipairs(specs) do
		if type(spec) == "string" then
			-- "user/repo" shorthand
			local path, mod_name = ensure_repo(spec)
			if path then
				local layer = load_external(path, mod_name)
				if layer then
					candidates[layer.name] = layer
				end
			end
		elseif spec.import then
			-- Auto-discover from module path
			local mod_path = spec.import
			local dir = vim.fn.stdpath("config") .. "/lua/" .. mod_path:gsub("%.", "/")
			if vim.uv.fs_stat(dir) then
				for entry, entry_type in vim.fs.dir(dir) do
					if entry_type == "directory" then
						local ok, layer = pcall(require, mod_path .. "." .. entry)
						if ok and type(layer) == "table" and layer.name then
							layer._import_path = mod_path .. "." .. entry
							candidates[layer.name] = layer
						end
					end
				end
			end
		elseif spec.dir then
			-- Local directory
			local expanded = vim.fn.expand(spec.dir)
			if vim.uv.fs_stat(expanded) then
				local mod_name = vim.fn.fnamemodify(expanded, ":t")
				local overrides = extract_overrides(spec, { "dir" })
				local layer = load_external(expanded, mod_name, overrides)
				if layer then
					candidates[layer.name] = layer
				end
			else
				vim.notify("lazy-layers: directory not found: " .. expanded, vim.log.levels.WARN)
			end
		elseif type(spec[1]) == "string" then
			-- { "user/repo", ... } with overrides
			local path, mod_name = ensure_repo(spec[1])
			if path then
				local overrides = extract_overrides(spec, {})
				local layer = load_external(path, mod_name, overrides)
				if layer then
					candidates[layer.name] = layer
				end
			end
		elseif spec.name then
			-- Inline layer
			candidates[spec.name] = spec
		end
	end

	-- 2. Evaluate cond
	for name, layer in pairs(candidates) do
		if layer.cond and not layer.cond() then
			candidates[name] = nil
		end
	end

	-- 3. Prune layers with unmet dependencies
	local changed = true
	while changed do
		changed = false
		for name, layer in pairs(candidates) do
			for _, dep in ipairs(layer.dependencies or {}) do
				if not candidates[dep] then
					candidates[name] = nil
					changed = true
					break
				end
			end
		end
	end

	-- 4. Topological sort with cycle detection
	local sorted = {}
	local visited = {}
	local in_stack = {}

	local function visit(name)
		if in_stack[name] then
			vim.notify("lazy-layers: dependency cycle involving '" .. name .. "'", vim.log.levels.WARN)
			return
		end
		if visited[name] then
			return
		end
		in_stack[name] = true
		visited[name] = true
		local layer = candidates[name]
		if layer then
			for _, dep in ipairs(layer.dependencies or {}) do
				visit(dep)
			end
			table.insert(sorted, name)
		end
		in_stack[name] = nil
	end

	for name in pairs(candidates) do
		visit(name)
	end

	-- 5. Call init hooks and build result specs
	local result = {}
	local configs = {}

	for _, name in ipairs(sorted) do
		local layer = candidates[name]

		if layer.init then
			layer.init()
		end

		if layer.config then
			table.insert(configs, layer.config)
		end

		if layer.plugins then
			for _, plugin in ipairs(layer.plugins) do
				table.insert(result, plugin)
			end
		elseif layer._import_path then
			table.insert(result, { import = layer._import_path .. ".plugins" })
		end
	end

	-- 6. Schedule config hooks after lazy loads
	if #configs > 0 then
		vim.api.nvim_create_autocmd("User", {
			pattern = "LazyDone",
			once = true,
			callback = function()
				for _, fn in ipairs(configs) do
					fn()
				end
			end,
		})
	end

	-- 7. Register :Layers command
	vim.api.nvim_create_user_command("Layers", function()
		vim.print(sorted)
	end, { force = true })

	return result
end

return M
