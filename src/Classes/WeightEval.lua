local t_insert = table.insert
local s_format = string.format

local function isSameAsDefaultList(list)
	return list and #list == 2
		and list[1].stat == "FullDPS" and list[1].weightMult == 1.0
		and list[2].stat == "TotalEHP" and list[2].weightMult == 0.5
end

local function initStatSortSelectionList(list)
	t_insert(list,  {
		label = "Full DPS",
		stat = "FullDPS",
		weightMult = 1.0,
	})
	t_insert(list,  {
		label = "Effective Hit Pool",
		stat = "TotalEHP",
		weightMult = 0.5,
	})
end

local WeightEvalClass = newClass("WeightEval", function(self)
	self.modFlag = false
    self.statSortSelectionList = {}
end)

-- Popup to set stat weight multipliers for sorting
function WeightEvalClass:SetStatWeights(previousSelectionList)
	self.modFlag = true
	previousSelectionList = previousSelectionList or {}
	local controls = { }
	local statList = { }
	local sliderController = { index = 1 }
	local popupHeight = 285

	controls.ListControl = new("TradeStatWeightMultiplierListControl", {"TOPLEFT", nil, "TOPRIGHT"}, {-410, 45, 400, 200}, statList, sliderController)

	for _, stat in pairs(data.powerStatList) do
		if not stat.ignoreForItems and stat.label ~= "Name" then
			t_insert(statList, {
				label = "0      :  "..stat.label,
				stat = {
					label = stat.label,
					stat = stat.stat,
					transform = stat.transform,
					weightMult = 0,
				}
			})
		end
	end

	controls.SliderLabel = new("LabelControl", { "TOPLEFT", nil, "TOPRIGHT" }, {-410, 20, 0, 16}, "^7"..statList[1].stat.label..":")
	controls.Slider = new("SliderControl", { "TOPLEFT", controls.SliderLabel, "TOPRIGHT" }, {20, 0, 150, 16}, function(value)
		if value == 0 then
			controls.SliderValue.label = "^7Disabled"
			statList[sliderController.index].stat.weightMult = 0
			statList[sliderController.index].label = s_format("%d      :  ", 0)..statList[sliderController.index].stat.label
		else
			controls.SliderValue.label = s_format("^7%.2f", 0.01 + value * 0.99)
			statList[sliderController.index].stat.weightMult = 0.01 + value * 0.99
			statList[sliderController.index].label = s_format("%.2f :  ", 0.01 + value * 0.99)..statList[sliderController.index].stat.label
		end
	end)
	controls.SliderValue = new("LabelControl", { "TOPLEFT", controls.Slider, "TOPRIGHT" }, {20, 0, 0, 16}, "^7Disabled")
	sliderController.SliderLabel = controls.SliderLabel
	sliderController.Slider = controls.Slider
	sliderController.SliderValue = controls.SliderValue

	for _, statBase in ipairs(self.statSortSelectionList) do
		for _, stat in ipairs(statList) do
			if stat.stat.stat == statBase.stat then
				stat.stat.weightMult = statBase.weightMult
				stat.label = s_format("%.2f :  ", statBase.weightMult)..statBase.label
				if statList[sliderController.index].stat.stat == statBase.stat then
					controls.Slider:SetVal(statBase.weightMult == 1 and 1 or statBase.weightMult - 0.01)
				end
			end
		end
	end

	controls.finalise = new("ButtonControl", { "BOTTOM", nil, "BOTTOM" }, {-90, -10, 80, 20}, "Save", function()
		main:ClosePopup()

		-- used in ItemsTab to save to xml under TradeSearchWeights node
		local statSortSelectionList = {}
		for stat, statTable in pairs(statList) do
			if statTable.stat.weightMult > 0 then
				t_insert(statSortSelectionList, statTable.stat)
			end
		end
		if (#statSortSelectionList) > 0 then
			--THIS SHOULD REALLY GIVE A WARNING NOT JUST USE PREVIOUS
			self.statSortSelectionList = statSortSelectionList
		end
    end)
	controls.cancel = new("ButtonControl", { "BOTTOM", nil, "BOTTOM" }, { 0, -10, 80, 20 }, "Cancel", function()
		if previousSelectionList and #previousSelectionList > 0 then
			self.statSortSelectionList = copyTable(previousSelectionList, true)
		end
		main:ClosePopup()
	end)
	controls.reset = new("ButtonControl", { "BOTTOM", nil, "BOTTOM" }, { 90, -10, 80, 20 }, "Reset", function()
		local previousSelection = { }
		if isSameAsDefaultList(self.statSortSelectionList) then
			previousSelection = copyTable(previousSelectionList, true)
		else
			previousSelection = copyTable(self.statSortSelectionList, true) -- this is so we can revert if user hits Cancel after Reset
		end
		self.statSortSelectionList = { }
		initStatSortSelectionList(self.statSortSelectionList)
		main:ClosePopup()
		self:SetStatWeights(previousSelection)
	end)
	main:OpenPopup(420, popupHeight, "Stat Weight Multipliers", controls)
end

function WeightEvalClass:WeightedImprovementPercentOutputs(baseOutput, newOutput)
	local result = 0.0
	for _, statTable in pairs(self.statSortSelectionList) do
		local stat = statTable.stat
		local weightMult = statTable.weightMult
		local newVal = (newOutput[stat] or 0.0)
		local oldVal = (baseOutput[stat] or 0.0)
		local delta = newVal - oldVal
		local div = oldVal
		if div > -0.0001 and div < 0.0001 then
			div = 1.0
		end
		result = result + delta / div * weightMult
	end
	return result * 100
end

function WeightEvalClass:WeightedOutputs(baseOutput, newOutput)
	return self:WeightedImprovementPercentOutputs(baseOutput, newOutput)
end

function WeightEvalClass:Save(xml)
	if self.statSortSelectionList then
		local parent = {
			elem = "WeightEval"
		}
		for _, statSort in ipairs(self.statSortSelectionList) do
			if statSort.weightMult and statSort.weightMult > 0 then
				local child = {
				elem = "Stat",
				attrib = {
					label = statSort.label,
					stat = statSort.stat,
					weightMult = s_format("%.2f", tostring(statSort.weightMult))
				}
			}
			t_insert(parent, child)
			end
		end
		t_insert(xml, parent)
	end
end

function WeightEvalClass:Load(xml, dbFileName)
	for _, node in ipairs(xml) do
		if node.elem == "WeightEval" then
			for _, child in ipairs(node) do
				local statSort = {
					label = child.attrib.label,
					stat = child.attrib.stat,
					weightMult = tonumber(child.attrib.weightMult)
				}
				t_insert(self.statSortSelectionList, statSort)
			end
		end
	end
end

function WeightEvalClass:PostLoad()
	if #self.statSortSelectionList == 0 then
		initStatSortSelectionList(self.statSortSelectionList)
	end
end
