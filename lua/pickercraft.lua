local PickerPresenter = require("presenter")
local PickerModel = require("model")
local PickerView = require("view")

local M = {}
-----------------------------------------------------------------------
-- Config
-----------------------------------------------------------------------
M.config = {
	file = {
		cmd = "ag",
		args = function(input)
			return { "-g", input }
		end,
	},
	grep = {
		cmd = "ag",
		args = function(input)
			return { "--vimgrep", input }
		end,
	},
	sort = {
		cmd = "fzy",
		args = function(input)
			return { "-e", input }
		end,
	},
	preview = {
		cmd = "cat",
		args = function(input)
			return { input }
		end,
	},
}

-----------------------------------------------------------------------
-- File picker
-----------------------------------------------------------------------
function M.file_finder()
	local pm = PickerModel.new({
		commands = { M.config.file, M.config.sort },
		pcommands = { M.config.preview },
	})
	local pv = PickerView.new()
	local pp = PickerPresenter.new(pm, pv)
	pv.presenter = pp
	pv:mount()
end

-----------------------------------------------------------------------
-- Live grep picker
-----------------------------------------------------------------------
function M.live_grep()
	local pm = PickerModel.new({
		commands = { M.config.grep, M.config.sort },
		pcommands = { M.config.preview },
	})
	local pv = PickerView.new()
	local pp = PickerPresenter.new(pm, pv)
	pv.presenter = pp
	pv:mount()
end

function M.register_commands()
	vim.api.nvim_create_user_command("PickerFiles", function()
		M.file_finder()
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
