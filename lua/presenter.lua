local function debounce(fn, ms)
	local timer = vim.loop.new_timer()
	return function(...)
		local args = { ... }
		timer:stop()
		timer:start(ms, 0, function()
			vim.schedule(function()
				fn(unpack(args))
			end)
		end)
	end
end

--- @class PickerPresenter
--- @field model PickerModel istance of the model
--- @field view PickerView view of the picker
--- @field debounced_search fun(pattern: string): nil
local PickerPresenter = {}
PickerPresenter.__index = PickerPresenter

--- Create a new presenter
--- @param model PickerModel
--- @param view PickerView
function PickerPresenter.new(model, view)
	local self = setmetatable({}, PickerPresenter)
	self.model = model
	self.view = view
	self.debounced_search = debounce(function(pattern)
		self:_do_search(pattern)
	end, 80)
	return self
end

--- Orchestrate picker closing
--- @return nil
function PickerPresenter:on_close()
	self.model:cancel()
	self.view:umount()
end

--- Orchestrate picker moving up in the results
--- @param selection number
--- @return nil
function PickerPresenter:on_move(selection)
	self.view:move(selection, #self.model.results)
	local item = self.model.results[selection]
	self.model:preview(item.file, function(content)
		self.view.preview(item, content)
	end)
end

--- Open the selected result
--- @param selected number
function PickerPresenter:on_open(selected)
	local item = self.model.results[selected]
	if not item then
		return
	end
	self.view:umount()
	vim.cmd("edit " .. vim.fn.fnameescape(item.file))
	vim.api.nvim_win_set_cursor(0, { item.line, item.col - 1 })
end

function PickerPresenter:_do_search(pattern)
	if pattern == "" then
		self.view:set_placeholder("Type to search...")
		return
	end

	self.model:search(pattern, function(results)
		self.view:show_results(results)
		local item = results[1]
		if item then
			self.model:preview(item.file, function(content)
				self.view:preview(item, content)
			end)
		end
	end)
end

function PickerPresenter:on_search(pattern)
	self.debounced_search(pattern)
end

return PickerPresenter
