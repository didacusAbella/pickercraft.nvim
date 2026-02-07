local M = {}

local api = vim.api
local fn = vim.fn
local uv = vim.loop

-- optional dependency
local has_devicons, devicons = pcall(require, "nvim-web-devicons")
local icon_cache = {}

local function get_icon(filename)
	if not has_devicons then
		return ""
	end

	local ext = filename:match("^.+%.(.+)$") or ""
	if icon_cache[ext] then
		return icon_cache[ext]
	end

	local icon = devicons.get_icon(filename, ext, { default = true }) or ""
	icon_cache[ext] = icon .. " "
	return icon_cache[ext]
end

-----------------------------------------------------------------------
-- Config
-----------------------------------------------------------------------
M.config = {
	list_cmd = { "ag", "-l" },
	filter_cmd = { "ag", "-g" },
	grep_cmd = { "ag", "--vimgrep" },

	sorter_cmd = { "fzy" },

	preview = {
		mode = "internal", -- "internal" or "external"
		cmd = { "bat", "--paging=never", "--color=always" },
	},
}

-----------------------------------------------------------------------
-- State (shared)
-----------------------------------------------------------------------
local state = {
	results = {},
	selection = 1,

	prompt_buf = nil,
	result_buf = nil,
	preview_buf = nil,

	prompt_win = nil,
	result_win = nil,
	preview_win = nil,

	mode = "files", -- "files" | "grep"

	job = nil, -- current running job
	job_token = 0, -- token for handling jobs
	preview_token = 0, -- token for handling preview
}

-----------------------------------------------------------------------
-- Utils
-----------------------------------------------------------------------
local function debounce(fn, delay)
	local timer = uv.new_timer()
	return function(...)
		local args = { ... }
		timer:stop()
		timer:start(delay, 0, function()
			vim.schedule(function()
				fn(unpack(args))
			end)
		end)
	end
end

local function create_buf()
	local buf = api.nvim_create_buf(false, true)
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false
	vim.bo[buf].buftype = "nofile"
	return buf
end

local function create_win(buf, row, height)
	return api.nvim_open_win(buf, false, {
		relative = "editor",
		row = row,
		col = math.floor(vim.o.columns * 0.1),
		width = math.floor(vim.o.columns * 0.8),
		height = height,
		style = "minimal",
		border = "rounded",
	})
end

local function get_prompt_text(buf)
	local line = api.nvim_buf_get_lines(buf, 0, 1, false)[1] or ""
	return line:gsub("^> ", "")
end

-----------------------------------------------------------------------
-- Run command (generic)
-----------------------------------------------------------------------
local function cancel_job()
	if state.job and state.job.stdin then
		state.job:shutdown()
		state.job = nil
	end
end

local function run_cmd(cmd, cb)
	cancel_job()

	state.job_token = state.job_token + 1
	local my_token = state.job_token

	state.job = vim.system(cmd, { text = true }, function(res)
		state.job = nil

		if my_token ~= state.job_token then
			return
		end

		if res.code == 0 and res.stdout then
			local lines = vim.split(res.stdout, "\n", { trimempty = true })
			vim.schedule(function()
				cb(lines)
			end)
		else
			vim.schedule(function()
				cb({})
			end)
		end
	end)
end

-----------------------------------------------------------------------
-- Search commands (generic names)
-----------------------------------------------------------------------
local function run_list_cmd(cb)
	run_cmd(M.config.list_cmd, cb)
end

local function run_filter_cmd(pattern, cb)
	local cmd = vim.deepcopy(M.config.filter_cmd)
	vim.list_extend(cmd, { pattern })
	run_cmd(cmd, cb)
end

local function run_grep_cmd(pattern, cb)
	local cmd = vim.deepcopy(M.config.grep_cmd)
	vim.list_extend(cmd, { pattern })
	run_cmd(cmd, cb)
end

-----------------------------------------------------------------------
-- Sorter command (generic)
-----------------------------------------------------------------------
local function run_sorter_cmd(items, cb)
	if #items == 0 then
		cb(items)
		return
	end

	cancel_job()

	state.job_token = state.job_token + 1
	local my_token = state.job_token

	local cmd = vim.deepcopy(M.config.sorter_cmd)

	state.job = vim.system(cmd, { text = true, stdin = table.concat(items, "\n") }, function(res)
		state.job = nil

		if my_token ~= state.job_token then
			return
		end

		if res.code == 0 and res.stdout then
			local lines = vim.split(res.stdout, "\n", { trimempty = true })
			vim.schedule(function()
				cb(lines)
			end)
		else
			vim.schedule(function()
				cb(items)
			end)
		end
	end)
end

-----------------------------------------------------------------------
-- Grep parser
-----------------------------------------------------------------------
local function parse_grep_line(line)
	local file, l, c, m = line:match("^(.-):(%d+):(%d+):(.*)$")
	if not file then
		return nil
	end
	return {
		raw = line,
		file = file,
		line = tonumber(l),
		col = tonumber(c),
		match = m,
	}
end

-----------------------------------------------------------------------
-- UI updates
-----------------------------------------------------------------------
local function ensure_selection_in_view()
	local win_h = api.nvim_win_get_height(state.result_win)
	local top = api.nvim_win_get_cursor(state.result_win)[1]
	local sel = state.selection

	if sel < top then
		api.nvim_win_set_cursor(state.result_win, { sel, 0 })
	elseif sel >= top + win_h then
		api.nvim_win_set_cursor(state.result_win, { sel - win_h + 1, 0 })
	end
end

local function format_result(item)
	if state.mode == "files" then
		return get_icon(item) .. item
	else
		return get_icon(item.file) .. string.format("%s:%d:%d: %s", item.file, item.line, item.col, item.match)
	end
end

local function clear_highlights()
	pcall(api.nvim_buf_clear_namespace, state.result_buf, -1, 0, -1)
end

local function highlight_preview_match(line_nr, col_start, col_end)
	pcall(api.nvim_buf_clear_namespace, state.preview_buf, -1, 0, -1)
	api.nvim_buf_add_highlight(state.preview_buf, -1, "Search", line_nr, col_start, col_end)
end

local function update_results(lines)
	if state.mode == "files" then
		state.results = lines
	else
		local parsed = {}
		for _, l in ipairs(lines) do
			local p = parse_grep_line(l)
			if p then
				table.insert(parsed, p)
			end
		end
		state.results = parsed
	end

	state.selection = 1

	vim.bo[state.result_buf].modifiable = true
	api.nvim_buf_set_lines(state.result_buf, 0, -1, false, vim.tbl_map(format_result, state.results))
	vim.bo[state.result_buf].modifiable = false

	api.nvim_win_set_cursor(state.result_win, { 1, 0 })
	M.update_preview()
end

-----------------------------------------------------------------------
-- Preview (internal or external) + line numbers
-----------------------------------------------------------------------
local function preview_internal(file, line, token)
	if token ~= state.preview_token then
		return
	end

	local ok, content = pcall(fn.readfile, file)
	if not ok then
		return
	end

	vim.bo[state.preview_buf].modifiable = true
	api.nvim_buf_set_lines(state.preview_buf, 0, -1, false, content)
	vim.bo[state.preview_buf].modifiable = false

	vim.wo[state.preview_win].number = true
	vim.wo[state.preview_win].relativenumber = false

	-- syntax nativa
	local ft = vim.filetype.match({ filename = file })
	if ft and ft ~= "" then
		vim.bo[state.preview_buf].filetype = ft
		vim.bo[state.preview_buf].syntax = ft
		pcall(vim.cmd, "doautocmd FileType " .. ft)
	end

	if line then
		api.nvim_win_set_cursor(state.preview_win, { line, 0 })

		-- highlight match only for grep
		if state.mode == "grep" then
			local item = state.results[state.selection]
			if item and item.line == line then
				local col_start = item.col - 1
				local col_end = col_start + #item.match
				highlight_preview_match(line - 1, col_start, col_end)
			end
		end
	end
end

local function preview_external(file, token)
	local cmd = vim.deepcopy(M.config.preview.cmd)
	vim.list_extend(cmd, { file })

	vim.system(cmd, { text = true }, function(res)
		if token ~= state.preview_token then
			return
		end

		local lines = {}
		if res.code == 0 and res.stdout then
			lines = vim.split(res.stdout, "\n", { trimempty = false })
		end

		vim.schedule(function()
			vim.bo[state.preview_buf].modifiable = true
			api.nvim_buf_set_lines(state.preview_buf, 0, -1, false, lines)
			vim.bo[state.preview_buf].modifiable = false
		end)
	end)
end

function M.update_preview()
	state.preview_token = state.preview_token + 1
	local my_token = state.preview_token

	local item = state.results[state.selection]
	if not item then
		return
	end

	local file = state.mode == "files" and item or item.file
	local line = state.mode == "grep" and item.line or nil

	if M.config.preview.mode == "internal" then
		preview_internal(file, line, my_token)
	else
		preview_external(file, my_token)
	end
end

-----------------------------------------------------------------------
-- Move selection
-----------------------------------------------------------------------
function M.move(delta)
	local new = state.selection + delta
	if new < 1 then
		new = 1
	end
	if new > #state.results then
		new = #state.results
	end
	state.selection = new

	api.nvim_win_set_cursor(state.result_win, { new, 0 })
	ensure_selection_in_view()
	M.update_preview()
end

-----------------------------------------------------------------------
-- Open file
-----------------------------------------------------------------------
function M.open()
	local item = state.results[state.selection]
	if not item then
		return
	end

	M.close()

	if state.mode == "files" then
		vim.cmd("edit " .. fn.fnameescape(item))
	else
		vim.cmd("edit " .. fn.fnameescape(item.file))
		api.nvim_win_set_cursor(0, { item.line, item.col - 1 })
	end
end

-----------------------------------------------------------------------
-- Close picker
-----------------------------------------------------------------------
function M.close()
	cancel_job()

	state.job_token = state.job_token + 1
	state.preview_token = state.preview_token + 1

	for _, win in ipairs({
		state.prompt_win,
		state.result_win,
		state.preview_win,
	}) do
		if win and api.nvim_win_is_valid(win) then
			api.nvim_win_close(win, true)
		end
	end
end

-----------------------------------------------------------------------
-- Common picker UI
-----------------------------------------------------------------------
local function setup_ui()
	local total_h = math.floor(vim.o.lines * 0.7)
	local prompt_h = 1
	local gap = 2
	local result_h = math.floor(total_h * 0.4)
	local preview_h = total_h - prompt_h - result_h - gap * 2 - 2
	local row = math.floor(vim.o.lines * 0.15)

	state.prompt_buf = create_buf()
	state.result_buf = create_buf()
	state.preview_buf = create_buf()

	state.prompt_win = create_win(state.prompt_buf, row, prompt_h)
	state.result_win = create_win(state.result_buf, row + prompt_h + gap, result_h)
	state.preview_win = create_win(state.preview_buf, row + prompt_h + gap + result_h + gap, preview_h)

	vim.bo[state.prompt_buf].buftype = "prompt"
	fn.prompt_setprompt(state.prompt_buf, "> ")

	vim.api.nvim_set_option_value("cursorline", true, { win = state.result_win })
	vim.api.nvim_set_option_value("winhighlight", "CursorLine:Visual", { win = state.result_win })

	-- prompt keymaps
	api.nvim_buf_set_keymap(state.prompt_buf, "i", "<Esc>", "", {
		callback = M.close,
		noremap = true,
		silent = true,
	})

	api.nvim_buf_set_keymap(state.prompt_buf, "i", "<Down>", "", {
		callback = function()
			M.move(1)
		end,
		noremap = true,
		silent = true,
	})

	api.nvim_buf_set_keymap(state.prompt_buf, "i", "<Up>", "", {
		callback = function()
			M.move(-1)
		end,
		noremap = true,
		silent = true,
	})

	api.nvim_buf_set_keymap(state.prompt_buf, "i", "<CR>", "", {
		callback = M.open,
		noremap = true,
		silent = true,
	})

	-- result keymap
	api.nvim_buf_set_keymap(state.result_buf, "n", "<CR>", "", {
		callback = M.open,
		noremap = true,
		silent = true,
	})

	api.nvim_buf_set_keymap(state.result_buf, "n", "<C-k>", "", {
		callback = function()
			api.nvim_set_current_win(state.prompt_win)
			vim.cmd("startinsert")
		end,
		noremap = true,
		silent = true,
	})

	api.nvim_create_autocmd("CursorMoved", {
		buffer = state.result_buf,
		callback = function()
			local line = api.nvim_win_get_cursor(state.result_win)[1]
			state.selection = line
			M.update_preview()
		end,
	})
end

-----------------------------------------------------------------------
-- File picker
-----------------------------------------------------------------------
function M.open_picker()
	state.mode = "files"
	setup_ui()

	local function do_search()
		local text = get_prompt_text(state.prompt_buf)

		if text == "" then
			run_list_cmd(function(files)
				run_sorter_cmd(files, update_results)
			end)
		else
			run_filter_cmd(text, function(files)
				run_sorter_cmd(files, update_results)
			end)
		end
	end

	local on_query = debounce(do_search, 80)

	api.nvim_create_autocmd({ "TextChangedI", "TextChanged" }, {
		buffer = state.prompt_buf,
		callback = on_query,
	})

	do_search()

	api.nvim_set_current_win(state.prompt_win)
	vim.cmd("startinsert")
end

-----------------------------------------------------------------------
-- Live grep picker
-----------------------------------------------------------------------
function M.live_grep()
	state.mode = "grep"
	setup_ui()

	local function do_search()
		local text = get_prompt_text(state.prompt_buf)

		run_grep_cmd(text, function(lines)
			run_sorter_cmd(lines, update_results)
		end)
	end

	local on_query = debounce(do_search, 80)

	api.nvim_create_autocmd({ "TextChangedI", "TextChanged" }, {
		buffer = state.prompt_buf,
		callback = on_query,
	})

	do_search()

	api.nvim_set_current_win(state.prompt_win)
	vim.cmd("startinsert")
end

function M.register_commands()
	vim.api.nvim_create_user_command("PickerFiles", function()
		M.open_picker()
	end, {})

	vim.api.nvim_create_user_command("PickerGrep", function()
		M.live_grep()
	end, {})
end

function M.setup(opts)
	opts = opts or {}
	M.config = vim.tbl_deep_extend("force", M.config, opts)
	M.register_commands()
end

return M
