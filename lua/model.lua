local CommandPipeline = require("pickercraft.pipeline")

---@class PickerResult
---@field raw string
---@field file string|nil
---@field line number|nil
---@field col number|nil
---@field match string|nil

---@class PickerModel the model underneath the picker
---@field pipeline CommandPipeline
---@field pwipeline CommandPipeline
---@field results PickerResult[]
---@field is_loading boolean
local PickerModel = {}
PickerModel.__index = PickerModel

--- Create a new PickerModel
--- @param opts table the option table
--- @return PickerModel
function PickerModel.new(opts)
	local self = setmetatable({}, PickerModel)

	self.pipeline = CommandPipeline.new(opts.commands)
	self.pwipeline = CommandPipeline.new(opts.pcommands)
	self.results = {}
	self.is_loading = false
	self.is_loading_preview = false
	return self
end

--- Start a search
--- @param query string the searh string
--- @param on_update fun(results: PickerResult[]):nil callback with results
function PickerModel:search(query, on_update)
	self.is_loading = true

	self.pipeline:run({ input = query }, function(output, err)
		self.is_loading = false

		if err then
			self.results = {}
		end

		self.results = self:_parse(output)
		on_update(self.results)
	end)
end

--- Cancel the actual pipeline
function PickerModel:cancel()
	self.pipeline:cancel()
	self.pwipeline:cancel()
	self.is_loading = false
end

--- Parse a pipeline output to vimgrep output
--- @param lines string[] the lines to parse
--- @return PickerResult[]
function PickerModel:_parse(lines)
	local results = {}

	if #lines == 0 then
		return results
	end

	for _, line in ipairs(lines) do
		local result = {
			raw = line,
			file = line,
			line = 1,
			col = 1,
			match = nil,
		}
		local file, lnum, col, match = line:match("^([^:]+):(%d+):(%d+):(.*)$")
		if file and lnum and col then
			result.file = file
			result.line = tonumber(lnum)
			result.col = tonumber(col)
			result.match = match
		else
			result.file = line
		end
		table.insert(results, result)
	end

	return results
end

function PickerModel:preview(file, on_content)
	self.is_loading_preview = true

	self.pwipeline:run({ input = file }, function(output, err)
		self.is_loading_preview = false

		if err then
			on_content({ "Cannot show preview" })
		end
		on_content(output)
	end)
end

return PickerModel
