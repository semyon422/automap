local NoteChart = {}

local NoteChart_metatable = {}
NoteChart_metatable.__index = NoteChart

NoteChart.new = function(self)
	local noteChart = {}
	
	setmetatable(noteChart, NoteChart_metatable)
	
	return noteChart
end

NoteChart.parse = function(self, filePath)
	self.filePath = filePath
	local file, err = io.open(filePath, "r")
	if err then print(err) end
	self.noteData = {}

	self.currentBlockName = ""
	for line in file:lines() do
		if line:find("^%[") then
			self.currentBlockName = line:match("^%[(.+)%]")
		else
			if line:find("^%a+:.*$") then
				local key, value = line:match("^(%a+):%s?(.*)")
				if key == "CircleSize" then
					self.columnCount = tonumber(value)
				elseif key == "Version" then
					self.baseVersion = value
				end
			elseif self.currentBlockName == "Events" and line:find("^%d-,%d-,\".+\"") then
				self.bgName = line:match("^.-,.-,\"(.+)\"")
			elseif self.currentBlockName == "HitObjects" and line ~= "" then
				local note = {}
				note.data = line:split(",")
				note.columnIndex = math.min(math.max(math.ceil(tonumber(note.data[1]) / 512 * self.columnCount), 1), self.columnCount)
				note.baseColumnIndex = note.columnIndex
				
				note.startTime = tonumber(note.data[3])
				note.endTime = note.startTime
				if bit.band(tonumber(note.data[4]), 128) == 128 then
					note.addition = note.data[6]:split(":")
					note.endTime = tonumber(note.addition[1])
					table.remove(note.addition, 1)
					note.addition = table.concat(note.addition, ":")
				end
				
				if note.startTime ~= note.endTime then
					self.long = true
				end
				
				table.insert(self.noteData, note)
			end
		end
	end
	file:close()
	
	table.sort(self.noteData, function(a, b) return a.startTime < b.startTime end)
	self.noteCount = #self.noteData
	
	return self
end

NoteChart.export = function(self, filePath)
	local file = io.open(self.filePath, "r")
	
	local output = {}
	for line in file:lines() do
		if line:find("[HitObjects]", 1, true) then
			table.insert(output, line)
			break
		elseif line:find("CircleSize:", 1, true) then
			table.insert(output, "CircleSize:" .. self.columnCount)
		elseif line:find("Version:", 1, true) then
			table.insert(output, "Version:" .. self.version)
		else
			table.insert(output, line)
		end
	end
	file:close()
	
	local addition = "0:0:0:0:"
	for _, note in pairs(self.noteData) do
		local x = math.floor((note.columnIndex - 0.5) * (512 / self.columnCount))
		
		if note.startTime ~= note.endTime then
			local data = note.data or {0, 0, 0, 128, 0, addition}
			table.insert(output, table.concat({
				x, 192, math.floor(note.startTime), data[4], data[5], note.endTime .. ":" .. addition
			}, ","))
		else
			local data = note.data or {0, 0, 0, 1, 0, addition}
			table.insert(output, table.concat({
				x, 192, math.floor(note.startTime), data[4], data[5], data[6]
			}, ","))
		end
	end
	
	local file, err = io.open(filePath, "w")
	if err then print(err) end
	file:write(table.concat(output, "\n"))
	file:close()
	
	return self
end

return NoteChart
