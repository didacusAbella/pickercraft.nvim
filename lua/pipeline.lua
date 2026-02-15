---@class CommandPipeline
---@field commands table[]
---@field _handles table
---@field _run_id number
---@field _running boolean
local CommandPipeline = {}
CommandPipeline.__index = CommandPipeline

function CommandPipeline.new(commands)
	return setmetatable({
		commands = commands or {},
		_handles = {},
		_run_id = 0,
		_running = false,
	}, CommandPipeline)
end

function CommandPipeline:add(cmd, args)
	table.insert(self.commands, {
		cmd = cmd,
		args = args or {},
	})
end

function CommandPipeline:is_running()
	return self._running
end

function CommandPipeline:cancel()
	if not self._running then
		return
	end

	self._run_id = self._run_id + 1
	self:_kill_all()
	self._running = false
end

---@param opts table|nil { input = string|nil }
---@param on_done fun(lines:string[], err:string|nil)
function CommandPipeline:run(opts, on_done)
	opts = opts or {}
	local input = opts.input

	self._run_id = self._run_id + 1
	local my_run_id = self._run_id

	self:_kill_all()
	self._handles = {}
	self._running = true

	local function finish(output, err)
		if my_run_id ~= self._run_id then
			return
		end

		self._running = false
		self._handles = {}

		if err then
			return on_done({}, err)
		end

		on_done(self:_split_lines(output or ""), nil)
	end

	local function fail(errmsg)
		self:_kill_all()
		finish("", errmsg)
	end

	local function step(index, stdin_data)
		if my_run_id ~= self._run_id then
			return
		end

		local command = self.commands[index]
		if not command then
			return finish(stdin_data or "")
		end

		local cmd = { command.cmd }
		vim.list_extend(cmd, command.args or {})

		local handle = vim.system(cmd, {
			text = true,
			stdin = stdin_data,
		}, function(obj)
			vim.schedule(function()
				if my_run_id ~= self._run_id then
					return
				end

				if obj.code ~= 0 and obj.code ~= 1 then
					return fail(string.format("Command failed: %s (exit %d)", command.cmd, obj.code))
				end

				step(index + 1, obj.stdout or "")
			end)
		end)

		table.insert(self._handles, handle)
	end

	step(1, input)
end

function CommandPipeline:_kill_all()
	for _, handle in ipairs(self._handles) do
		pcall(function()
			handle:kill(15)
		end)
	end
	self._handles = {}
end

function CommandPipeline:_split_lines(output)
	output = vim.trim(output or "")
	if output == "" then
		return {}
	end

	-- Usa vim.split per robustezza
	return vim.split(output, "\n", {
		trimempty = true,
	})
end

return CommandPipeline
