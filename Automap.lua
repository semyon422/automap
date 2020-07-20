local Container = require("aqua.graphics.Container")
local CS = require("aqua.graphics.CS")
local Button = require("aqua.ui.Button")
local Observer = require("aqua.util.Observer")
local aquaio = require("aqua.io")
require("aqua.string")

local NoteChart = require("NoteChart")
local Upscaler = require("libchart.Upscaler")
local NoteBlock = require("libchart.NoteBlock")
local BlockFinder = require("libchart.BlockFinder")
local NotePreprocessor = require("libchart.NotePreprocessor")
local SolutionSeeker = require("libchart.SolutionSeeker")

local config = require("config")

local ffi = require('ffi')
local liblove = ffi.load('love')

ffi.cdef [[
	int PHYSFS_setWriteDir(const char *newDir);
]]

local setWriteDir = function(path)
	return liblove.PHYSFS_setWriteDir(path)
end

local Automap = {}

Automap.font = love.graphics.newFont("NotoMono-Regular.ttf", 20)
Automap.targetMode = 10

math.randomseed(os.time())
Automap.colorCounter = math.random(0, 300)

Automap.init = function(self)
	self.observer = Observer:new()
	self.observer.receive = function(_, ...) return self:receive(...) end
end

Automap.run = function(self)
	self:init()
	self:load()
	aquaio:add(self.observer)
end

Automap.infoString = [[
Use left and right arrows
or mouse wheel
to change output keymode.
Drop beatmap here to convert.
Current keymode: %d

Press F1 to switch
between stable and beta version
]]

Automap.versionString = [[
Automap v5.0.8
]]

Automap.load = function(self)
	self.cs = CS:new({
		bx = 0,
		by = 0,
		rx = 0,
		ry = 0,
		binding = "all",
		baseOne = 512
	})
	
	self.state = 0
	
	self.info = Button:new({
		text = "",
		x = 0,
		y = 0,
		w = 1,
		h = 1,
		cs = self.cs,
		mode = "fill",
		rectangleColor = {0, 0, 0, 0},
		textColor = {255, 255, 255, 255},
		textAlign = {x = "center", y = "center"},
		limit = 1,
		font = self.font
	})
	
	self.info.text = self.infoString:format(self.targetMode)
	self.info:reload()
	
	self.version = Button:new({
		text = self.versionString,
		x = 0,
		y = 0,
		w = 1,
		h = 1,
		cs = self.cs,
		mode = "fill",
		rectangleColor = {0, 0, 0, 0},
		textColor = {255, 255, 255, 255},
		textAlign = {x = "left", y = "left"},
		limit = 1,
		font = self.font
	})
	
	self.version:reload()
end

Automap.unload = function(self)
end

Automap.update = function(self, dt)
	love.timer.sleep(1/60)
	
	self.info:update()
	self.version:update()
	
	self:updateColor(dt)
end

Automap.draw = function(self)
	self.info:draw()
	self.version:draw()
end

Automap.updateColor = function(self, dt)
	self.colorCounter = self.colorCounter + dt / 10
	
	local c = self.colorCounter
	love.graphics.setBackgroundColor(
		(math.sin(c) + 1) / 2 * 128,
		(math.sin(c ^ 1.1) + 1) / 2 * 128,
		(math.sin(c ^ 1.2 + 2) + 1) / 2 * 128
	)
end

Automap.receive = function(self, event)
	if event.name == "update" then
		self:update(event.args[1])
	elseif event.name == "draw" then
		self:draw()
	elseif event.name == "quit" then
		os.exit()
	elseif event.name == "filedropped" then
		if self.extraMode then
			return self:processExtra(event.args[1])
		end
		self:process(event.args[1])
	elseif event.name == "keypressed" then
		local key = event.args[1]
		if key == "left" then
			self.targetMode = self.targetMode - 1
		elseif key == "right" then
			self.targetMode = self.targetMode + 1
		elseif key == "f1" then
			self.extraMode = not self.extraMode
			if self.extraMode then
				self.version.text = [[Automap v6.0.0 beta]]
			else
				self.version.text = [[Automap v5.0.8]]
			end
			self.version:reload()
		end
		self.info.text = self.infoString:format(self.targetMode)
		self.info:reload()
	elseif event.name == "wheelmoved" then
		local direction = event.args[2]
		self.targetMode = self.targetMode + direction
		self.info.text = self.infoString:format(self.targetMode)
		self.info:reload()
	end
end

Automap.process = function(self, file)
	local debugDiffs = false
	local baseFilePath = file:getFilename()
	local baseFileName = baseFilePath:match("^.+\\(.-)$")
	local basePath = baseFilePath:match("^(.+)\\.-$")
	setWriteDir(basePath)
			
	local nc = NoteChart:new()
	nc:parse(file)
	if nc.noteCount == 0 then
		self.info.text = "empty beatmap\n"
		self.info:reload()
		return
	elseif nc.mode ~= 3 then
		self.info.text = "wrong mode\n"
		self.info:reload()
		return
	end
	
	if not config[self.targetMode] or not config[self.targetMode][nc.columnCount] then
		self.info.text = "unsupported mode\n" .. nc.columnCount .. " -> " .. self.targetMode .. "\n" ..
			"configure it in config.lua"
		self.info:reload()
		return
	end
	
	Upscaler.columns = config[self.targetMode][nc.columnCount]
	
	NotePreprocessor.columnCount = nc.columnCount
	NotePreprocessor:process(nc.noteData)
	-- NotePreprocessor:print("np_notes.txt")

	local bf = BlockFinder:new()
	bf.noteData = nc.noteData
	bf.columnCount = nc.columnCount
	bf:process()

	local nbs = bf:getNoteBlocks()
	print("blocks", #nbs)

	if debugDiffs then
		local noteData = {}
		for _, nb in ipairs(nbs) do
			noteData[#noteData + 1] = {
				columnIndex = nb.baseColumnIndex,
				startTime = nb.startTime,
				endTime = nb.endTime
			}
		end

		nc.noteData = noteData
		nc.version = "automap: base blocks"
		nc:export(baseFileName .. ".bb.osu")
	end

	NotePreprocessor:process(nbs)
	NotePreprocessor:print("pgam.txt")
	-- NotePreprocessor:print("blocks.txt")

	local am = Upscaler:new()
	am.noteChart = nc
	am:load(self.targetMode)
	local notes, blocks = am:process(nbs)

	if debugDiffs then
		local noteData = {}
		for _, nb in ipairs(blocks) do
			noteData[#noteData + 1] = {
				columnIndex = nb.columnIndex,
				startTime = nb.startTime,
				endTime = nb.endTime
			}
		end

		nc.noteData = noteData
		nc.version = "automap: upscaled blocks"
		nc.columnCount = self.targetMode
		nc:export(baseFileName .. ".ub.osu")
	end

	nc.noteData = notes
	nc.version = "A" .. self.targetMode .. "K " .. nc.baseVersion
	nc.columnCount = self.targetMode
	nc:export(baseFileName .. ".a" .. self.targetMode .. ".osu")
end

local intersectSegment = function(tc, tm, bc, bm)
	return (
		math.max((tc - 1) / tm, math.min(tc / tm, bc / bm)) -
		math.min(tc / tm, math.max((tc - 1) / tm, (bc - 1) / bm))
	) * tm
end


Automap.processExtra = function(self, file)
	local debugDiffs = false
	local baseFilePath = file:getFilename()
	local baseFileName = baseFilePath:match("^.+\\(.-)$")
	local basePath = baseFilePath:match("^(.+)\\.-$")
	setWriteDir(basePath)
			
	local nc = NoteChart:new()
	nc:parse(file)
	if nc.noteCount == 0 then
		self.info.text = "empty beatmap\n"
		self.info:reload()
		return
	elseif nc.mode ~= 3 then
		self.info.text = "wrong mode\n"
		self.info:reload()
		return
	end
	
	NotePreprocessor.columnCount = nc.columnCount
	NotePreprocessor:process(nc.noteData)
	-- NotePreprocessor:print("np_notes.txt")

	local bf = BlockFinder:new()
	bf.noteData = nc.noteData
	bf.columnCount = nc.columnCount
	bf:process()

	local notes = bf:getNoteBlocks()
	print("blocks", #notes)

	local getDelta = function(i, lane)
		local startTime = notes[i].startTime
		for k = i - 1, 1, -1 do
			local cnote = notes[k]
			if cnote.lane == lane then
				return math.max(0, startTime - cnote.endTime)
			end
		end
		return startTime
	end

	local recursionLimit = 1

	local check
	check = function(noteIndex, lane)
		local rate = 1

		local note = notes[noteIndex]

		if not note then
			return rate
		end

		rate = rate * intersectSegment(lane, self.targetMode, note.columnIndex, nc.columnCount)
		if rate == 0 then return rate end

		rate = rate * getDelta(noteIndex, lane) / 1000
		if rate == 0 then return rate end

		if recursionLimit ~= 0 then
			recursionLimit = recursionLimit - 1
			local maxNextRate = 0
			for i = 1, self.targetMode do
				maxNextRate = math.max(maxNextRate, check(noteIndex + 1, i))
			end
			rate = rate * maxNextRate
			recursionLimit = recursionLimit + 1
		end

		return rate
	end
	
	local status, err = SolutionSeeker:solve(notes, self.targetMode, check)

	assert(status, err)
	for _, note in ipairs(notes) do
		assert(note.columnIndex, _)
		note.columnIndex = note.lane
	end

	local notes2 = {}
	for _, noteBlock in ipairs(notes) do
		for _, note in ipairs(noteBlock:getNotes()) do
			notes2[#notes2 + 1] = note
		end
	end

	nc.noteData = notes2
	nc.version = "6A" .. self.targetMode .. "K " .. nc.baseVersion
	nc.columnCount = self.targetMode
	nc:export(baseFileName .. ".6a" .. self.targetMode .. ".osu")
end

return Automap
