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

local config = require("config")

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
end

Automap.unload = function(self)
end

Automap.update = function(self, dt)
	love.timer.sleep(1/60)
	
	self.info:update()
	
	self:updateColor(dt)
end

Automap.draw = function(self)
	self.info:draw()
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
		self:process(event.args[1]:getFilename())
	elseif event.name == "keypressed" then
		local key = event.args[1]
		if key == "left" then
			self.targetMode = self.targetMode - 1
		elseif key == "right" then
			self.targetMode = self.targetMode + 1
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

Automap.process = function(self, basePath)
	local debugDiffs = false
	
	local nc = NoteChart:new()
	nc:parse(basePath)
	
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
		nc:export(basePath .. ".bb.osu")
	end

	NotePreprocessor:process(nbs)
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
		nc:export(basePath .. ".ub.osu")
	end

	nc.noteData = notes
	nc.version = "A" .. self.targetMode .. "K " .. nc.baseVersion
	nc.columnCount = self.targetMode
	nc:export(basePath .. ".a" .. self.targetMode .. ".osu")
end

return Automap
