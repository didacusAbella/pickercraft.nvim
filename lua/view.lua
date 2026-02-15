local api = vim.api
local fn = vim.fn
local has_devicons, devicons = pcall(require, "nvim-web-devicons")
local icon_cache = {}
local pkns = api.nvim_create_namespace("pickercraft")

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

local function format_result(item)
	if not item.match then
		return get_icon(item) .. item
	else
		return get_icon(item.file) .. string.format("%s:%d:%d: %s", item.file, item.line, item.col, item.match)
	end
end

--- @class PickerView the view of the picker
--- @field selection number the current selectled line
--- @field _pb number prompt buffer number
--- @field _rb number result buffer number
--- @field _pwb number preview buffer number
--- @field _pw number preview window number
--- @field _rw number = result window number
--- @field _pww number preview window number
--- @field presenter PickerPresenter the presenter
local PickerView = {}
PickerView.__index = PickerView

--- Create a new PickerView
--- @param presenter PickerPresenter
function PickerView.new(presenter)
	local self = setmetatable({}, PickerView)
	self._pb = create_buf()
	self._rb = create_buf()
	self._pwb = create_buf()
	self.selection = 1
	self._pw = nil
	self._rw = nil
	self._pww = nil
	self.presenter = presenter
	vim.bo[self._pb].buftype = "prompt"
	fn.prompt_setprompt(self._pb, "> ")

	-- prompt keymaps
	api.nvim_buf_set_keymap(self._pb, "i", "<Esc>", "", {
		callback = function()
			self.presenter:on_close()
		end,
		noremap = true,
		silent = true,
	})

	api.nvim_buf_set_keymap(self._pb, "i", "<Down>", "", {
		callback = function()
			self.presenter:on_move(self.selection + 1)
		end,
		noremap = true,
		silent = true,
	})

	api.nvim_buf_set_keymap(self._pb, "i", "<Up>", "", {
		callback = function()
			self.presenter:on_move(self.selection - 1)
		end,
		noremap = true,
		silent = true,
	})
	api.nvim_buf_set_keymap(self._pb, "i", "<CR>", "", {
		callback = function()
			self.presenter:on_open(self.selection)
		end,
		noremap = true,
		silent = true,
	})

	-- result keymap
	api.nvim_buf_set_keymap(self._rb, "n", "<CR>", "", {
		callback = function()
			self.presenter:on_open(self.selection)
		end,
		noremap = true,
		silent = true,
	})

	api.nvim_buf_set_keymap(self._rb, "n", "<C-k>", "", {
		callback = function()
			api.nvim_set_current_win(self._pb)
			vim.cmd("startinsert")
		end,
		noremap = true,
		silent = true,
	})

	api.nvim_create_autocmd("CursorMoved", {
		buffer = self._rb,
		callback = function()
			local line = api.nvim_win_get_cursor(self._rw)[1]
			self.selection = line
			self.presenter:on_move(self.selection)
		end,
	})

	api.nvim_create_autocmd({ "TextChangedI", "TextChanged" }, {
		buffer = self._pb,
		callback = function()
			local line = api.nvim_buf_get_lines(self._pb, 0, 1, false)[1] or ""
			self.presenter:on_search(line:gsub("^> ", ""))
		end,
	})
	return self
end

--- Mount the component
--- @return nil
function PickerView:mount()
	local total_h = math.floor(vim.o.lines * 0.7)
	local prompt_h = 1
	local gap = 2
	local result_h = math.floor(total_h * 0.4)
	local preview_h = total_h - prompt_h - result_h - gap * 2 - 2
	local row = math.floor(vim.o.lines * 0.15)
	self._pw = create_win(self._pb, row, prompt_h)
	self._rw = create_win(self._rb, row + prompt_h + gap, result_h)
	self._pww = create_win(self._pwb, row + prompt_h + gap + result_h + gap, preview_h)
	api.nvim_set_option_value("cursorline", true, { win = self._rw })
	api.nvim_set_option_value("winhighlight", "CursorLine:Visual", { win = self._rw })
	api.nvim_set_current_win(self._pw)
	vim.cmd("startinsert")
end

--- Unmount the component
--- @return nil
function PickerView:umount()
	for _, win in ipairs({
		self._pw,
		self._rw,
		self._pww,
	}) do
		if win and api.nvim_win_is_valid(win) then
			api.nvim_win_close(win, true)
		end
	end
end

--- move the selection
--- @param line number absolute line
--- @param result_size number
function PickerView:move(line, result_size)
	if result_size == 0 then
		return
	end

	if line < 1 then
		line = 1
	end

	if line > result_size then
		line = result_size
	end

	self.selection = line
	local win_h = api.nvim_win_get_height(self._rw)
	local top = api.nvim_win_get_cursor(self._rw)[1]

	if self.selection < top then
		api.nvim_win_set_cursor(self._rw, { self.selection, 0 })
	elseif self.selection >= top + win_h then
		api.nvim_win_set_cursor(self._rw, { self.selection - win_h + 1, 0 })
	end
end

--- @param results PickerResult[]
function PickerView:show_results(results)
	self.selection = 1
	vim.bo[self._rb].modifiable = true
	api.nvim_buf_set_lines(self._rb, 0, -1, false, vim.tbl_map(format_result, results))
	vim.bo[self._rb].modifiable = false
	api.nvim_win_set_cursor(self._rw, { 1, 0 })
end

function PickerView:preview(item, lines)
	vim.bo[self._pwb].modifiable = true
	api.nvim_buf_set_lines(self._pwb, 0, -1, false, lines)
	vim.bo[self._pwb].modifiable = false
	vim.wo[self._pww].number = true
	vim.wo[self._pww].relativenumber = false
	local ft = vim.filetype.match({ filename = item.file })

	if ft and ft ~= "" then
		vim.bo[self._pwb].filetype = ft
		vim.bo[self._pwb].suntax = ft
		pcall(vim.cmd, "aoautocmd FileType " .. ft)
	end

	if item.match then
		api.nvim_win_set_cursor(self._pww, { item.line, 0 })
		local col_start = item.col - 1
		local col_end = col_start + vim.str_utfindex(item.match, "utf-8")
		local line_nr = item.line - 1
		pcall(api.nvim_buf_clear_namespace, self._pwb, -1, 0, -1)
		vim.hl.range(self._pwb, pkns, "Search", { line_nr, col_start }, { line_nr, col_end }, { regtype = "v" })
	end
end

function PickerView:set_placeholder(text)
	vim.bo[self._rb].modifiable = true
	api.nvim_buf_set_lines(self._rb, 0, -1, false, { text })
	vim.bo[self._rb].modifiable = false
	api.nvim_win_set_cursor(self._rw, { 1, 0 })
	pcall(api.nvim_buf_clear_namespace, self._rb, -1, 0, -1)
end

return PickerView
