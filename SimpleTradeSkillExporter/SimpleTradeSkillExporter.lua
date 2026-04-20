-- SimpleTradeSkillExporter
-- Author: Hamma
-- Description: Exports trade skill recipes to plain text, CSV, or Markdown format.
--              Supports all classic WoW flavors (Vanilla, TBC, Wrath, Cata, MoP).
--              Use /tsexport or the Export button on the tradeskill window.

-- addonName: the addon's folder name injected by the WoW client.
-- tse: a shared namespace table for this addon; passed to every file via `...`.
local addonName, tse = ...

-- Map each supported WoW flavor to its Wowhead base URL.
-- WOW_PROJECT_ID is a client-injected global identifying which game flavor is running.
local wowheadUrls = {
	[WOW_PROJECT_MISTS_CLASSIC]           = "https://wowhead.com/mop-classic/",
	[WOW_PROJECT_CATACLYSM_CLASSIC]       = "https://wowhead.com/cata/",
	[WOW_PROJECT_WRATH_CLASSIC]           = "https://wowhead.com/wotlk/",
	[WOW_PROJECT_BURNING_CRUSADE_CLASSIC] = "https://wowhead.com/tbc/",
	[WOW_PROJECT_CLASSIC]                 = "https://wowhead.com/classic/",
}
tse.wowheadBase = wowheadUrls[WOW_PROJECT_ID]

-- Minimum output ID for crafted items/enchants introduced in each expansion.
-- Item IDs and enchant spell IDs are both assigned sequentially, so the same
-- floor applies to both. Vanilla has no floor — all recipes are always included.
local expansionItemIdFloors = {
	[WOW_PROJECT_MISTS_CLASSIC]           = 71000,
	[WOW_PROJECT_CATACLYSM_CLASSIC]       = 52000,
	[WOW_PROJECT_WRATH_CLASSIC]           = 35000,
	[WOW_PROJECT_BURNING_CRUSADE_CLASSIC] = 24000,
	[WOW_PROJECT_CLASSIC]                 = nil,
}
tse.expansionItemIdFloor = expansionItemIdFloors[WOW_PROJECT_ID]

-- Session state — persists last-used format and scope within a play session.
local selectedExportFormat = "text"
local selectedExportAll = false

local exportWindow
local openExportWindow
local createExportWindow

-- Parses the slash command message into export format and whether to include all expansions.
local validFormats = { text = true, csv = true, markdown = true }

-- Examples: "csv all" -> ("csv", true), "markdown" -> ("markdown", false), "" -> ("text", false), "foo" -> ("text", false) + warning
-- Unknown format values are normalised to "text" with a warning printed to chat.
local function parseCommand(msg)
	local parts = {}
	for part in msg:gmatch("%S+") do
		table.insert(parts, part)
	end

	local exportAll = parts[#parts] == "all"
	if exportAll then table.remove(parts, #parts) end

	local format = parts[1] or "text"
	if not validFormats[format] then
		print("|cffFF0000[TSE]:|r Unknown format '" .. format .. "', defaulting to text.")
		format = "text"
	end

	return format, exportAll
end

-- Returns the numeric ID of the crafted output for a recipe at the given index, or nil.
-- For most professions this is the item ID; for enchanting it is the enchant spell ID.
-- Both are assigned sequentially, so the same expansion floor applies to both.
local function getCraftedOutputId(index)
	local itemLink = GetTradeSkillItemLink(index)
	if not itemLink then return nil end
	local id = itemLink:match("item:(%d+)") or itemLink:match("enchant:(%d+)")
	return id and tonumber(id) or nil
end

-- Returns true if the recipe at index belongs to the current expansion.
-- Uses the crafted output ID as a proxy for expansion (IDs are assigned sequentially).
-- Includes the recipe if the output ID cannot be determined.
local function isCurrentExpansionRecipe(index)
	if not tse.expansionItemIdFloor then return true end
	local outputId = getCraftedOutputId(index)
	if outputId == nil then return true end
	return outputId >= tse.expansionItemIdFloor
end

-- Returns player info as a table for use in header building.
local function getPlayerInfo()
	local name = UnitName("player")
	local race = UnitRace("player")
	local class = UnitClass("player")
	local level = UnitLevel("player")
	local guild = GetGuildInfo("player") or "-"
	local server = GetRealmName()
	return { name = name, race = race, class = class, level = level, guild = guild, server = server }
end

-- Formats a single recipe entry based on the export type.
local function buildRecipeEntry(name, itemLink, exportType)
	if exportType == "csv" then
		return '=HYPERLINK("' .. tse.wowheadBase .. itemLink .. '","' .. name .. '")\n'
	elseif exportType == "markdown" then
		return "- [" .. name .. "](" .. tse.wowheadBase .. itemLink .. ")\n"
	else
		return name .. "\n"
	end
end

-- Builds the header block for the export window based on export type.
local function buildHeader(player, skillName, rank, recipeCount, exportType)
	local header

	if exportType == "markdown" then
		header =
			"**Player:** " .. player.name .. ", Level " .. player.level .. " " .. player.race .. " " .. player.class .. "  \n" ..
			"**Guild:** " .. player.guild .. "  \n" ..
			"**Server:** " .. player.server .. "  \n"
		if rank > 0 then
			header = header .. "**" .. skillName .. ":** Skill " .. rank .. ", " .. recipeCount .. " total recipes" .. "  \n"
		end
		header = header .. "\n"
	elseif exportType == "csv" then
		header = ""
	else
		header =
			"Player: " .. player.name .. ", Level " .. player.level .. " " .. player.race .. " " .. player.class .. "  \n" ..
			"Guild: " .. player.guild .. "  \n" ..
			"Server: " .. player.server .. "  \n"
		if rank > 0 then
			header = header .. skillName .. " skill " .. rank .. ", " .. recipeCount .. " total recipes" .. "  \n"
		end
		header = header .. "---------------------\n"
	end

	return header
end

-- Prints available slash commands to the chat window.
local function printHelp()
	print("\124cff00FF00tsexport:\124r \124cff00FF00S\124rimple \124cff00FF00T\124rradeskill \124cff00FF00E\124rxporter - Help")
	print("\124cff00FF00tsexport:\124r Type '/tsexport help' to show this message")
	print("\124cff00FF00tsexport:\124r Open a tradeskill window, then type one of the following commands")
	print("\124cff00FF00tsexport:\124r By default, only recipes for the current expansion are exported")
	print("\124cff00FF00tsexport:\124r Append '\124cff00FF00all\124r' to include recipes from all expansions")
	print("\124cff00FF00tsexport:\124r '/tsexport' or '/tsexport all' - plain text list")
	print("\124cff00FF00tsexport:\124r '/tsexport csv' or '/tsexport csv all' - Comma Separated Value list")
	print("\124cff00FF00tsexport:\124r '/tsexport markdown' or '/tsexport markdown all' - Markdown list")
end

-- Returns the Wowhead query string for a tradeskill entry, or nil if it cannot be resolved.
local function getItemLink(index)
	local itemLink, itemId

	itemLink = GetTradeSkillItemLink(index)
	if itemLink then
		itemId = itemLink:match("item:(%d+)") or itemLink:match("enchant:(%d+)")
		if itemId then
			return "item=" .. tonumber(itemId)
		end
	end

	itemLink = GetTradeSkillRecipeLink(index)
	if itemLink then
		itemId = itemLink:match("item:(%d+)") or itemLink:match("enchant:(%d+)")
		if itemId then
			return "spell=" .. tonumber(itemId)
		else
			print("|cffFF0000[TSE]: Unable to process entry " .. index)
			local craftedLink = GetTradeSkillItemLink(index)
			local spellLink = GetTradeSkillRecipeLink(index)
			if craftedLink then print(craftedLink:gsub('\124', '\124\124')) end
			if spellLink then print(spellLink:gsub('\124', '\124\124')) end
			return nil
		end
	end

	return nil
end

-- Queries the open trade skill window and stores all recipe data in tse.recipeData.
-- Each recipe captures its name, Wowhead link, and whether it belongs to the current expansion.
-- Storing this upfront means format/scope switching in the window never needs to re-query the API.
local function captureRecipeData()
	local skillName, skillRank = GetTradeSkillLine()
	if skillRank == 0 then return false end

	local recipes = {}
	for i = 1, GetNumTradeSkills() do
		local name, entryType = GetTradeSkillInfo(i)
		if name and entryType ~= "header" then
			table.insert(recipes, {
				name             = name,
				itemLink         = getItemLink(i),
				isCurrentExpansion = isCurrentExpansionRecipe(i),
			})
		end
	end

	tse.recipeData = {
		skillName = skillName,
		skillRank = skillRank,
		player    = getPlayerInfo(),
		recipes   = recipes,
	}

	return true
end

-- Queries trade skill data, sets the active format/scope, and opens the export window.
local function runExport(exportType, exportAll)
	if (exportType == "csv" or exportType == "markdown") and not tse.wowheadBase then
		print("\124cffFF0000Error:\124r CSV and Markdown exports are not supported on this version of WoW.")
		return
	end

	if not captureRecipeData() then
		print("\124cffFF0000Error:\124r Must open a tradeskill window. Type /tsexport help for more information.")
		return
	end

	selectedExportFormat = exportType
	selectedExportAll    = exportAll

	openExportWindow()
end

-- Attaches the TSExport button to TradeSkillFrame's title bar. Safe to call multiple times — creates once.
local function attachTradeSkillButton()
	if tse.tradeSkillButton then return end

	local button = CreateFrame("Button", nil, TradeSkillFrame, "UIPanelButtonTemplate")
	button:SetSize(72, 18)
	button:SetText("TSExport")
	-- Anchor to the right edge of the portrait so the button sits in the title bar without overlapping it.
	button:SetPoint("LEFT", TradeSkillFramePortrait, "RIGHT", 9, 12)
	button:SetScript("OnClick", function()
		runExport(selectedExportFormat, selectedExportAll)
	end)

	tse.tradeSkillButton = button
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("TRADE_SKILL_SHOW")
eventFrame:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" and arg1 == addonName then
		local version = GetAddOnMetadata(addonName, "Version") or "unknown"
		print("\124cff00FF00SimpleTradeSkillExporter v" .. version .. "\124r loaded. Type \124cff00FF00/tsexport help\124r for usage.")
		self:UnregisterEvent("ADDON_LOADED")
	elseif event == "TRADE_SKILL_SHOW" then
		attachTradeSkillButton()
	end
end)

SLASH_SIMPLETRADESKILLEXPORTER1 = "/tsexport"
SlashCmdList["SIMPLETRADESKILLEXPORTER"] = function(msg)
	if msg == "help" then
		printHelp()
		return
	end

	local exportType, exportAll = parseCommand(msg)
	runExport(exportType, exportAll)
end

-- Refreshes the export window title and edit box content from tse.recipeData
-- using the current selectedExportFormat and selectedExportAll.
openExportWindow = function()
	if not exportWindow then
		createExportWindow()
	end

	exportWindow.updateControls()
	exportWindow.refresh()
	exportWindow:Show()
end

createExportWindow = function()
	local frame = CreateFrame("Frame", nil, UIParent, "BasicFrameTemplateWithInset")
	frame:SetSize(640, 480)
	frame:SetPoint("CENTER")
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:SetClampedToScreen(true)
	frame:SetFrameStrata("HIGH")
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:SetScript("OnShow", function() frame.updateControls() end)

	frame.title = frame:CreateFontString(nil, "OVERLAY")
	frame.title:SetFontObject("GameFontHighlight")
	frame.title:SetPoint("LEFT", frame.TitleBg, 5, 0)

	-- Format toggle buttons and scope checkbox sit in a control bar at the top of the inset.
	local formats = {
		{ label = "Text",     value = "text" },
		{ label = "CSV",      value = "csv" },
		{ label = "Markdown", value = "markdown" },
	}

	frame.formatButtons = {}

	for i, fmt in ipairs(formats) do
		local btn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
		btn:SetSize(72, 22)
		btn:SetText(fmt.label)
		btn.value = fmt.value

		if i == 1 then
			btn:SetPoint("TOPLEFT", frame.InsetBg, "TOPLEFT", 4, -4)
		else
			btn:SetPoint("LEFT", frame.formatButtons[i - 1], "RIGHT", 4, 0)
		end

		if (fmt.value == "csv" or fmt.value == "markdown") and not tse.wowheadBase then
			btn:Disable()
		else
			btn:SetScript("OnClick", function()
				selectedExportFormat = btn.value
				frame.updateControls()
				frame.refresh()
			end)
		end

		frame.formatButtons[i] = btn
	end

	-- "All expansions" checkbox — hidden on Vanilla where all recipes are always included.
	local allCheckbox = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
	allCheckbox:SetPoint("LEFT", frame.formatButtons[#frame.formatButtons], "RIGHT", 10, 0)
	allCheckbox:SetChecked(selectedExportAll)
	allCheckbox.text:SetText("All expansions")
	allCheckbox:SetScript("OnClick", function()
		selectedExportAll = allCheckbox:GetChecked()
		frame.refresh()
	end)
	frame.allCheckbox = allCheckbox

	if not tse.expansionItemIdFloor then
		allCheckbox:Hide()
	end

	-- Scroll frame sits below the control bar and above the bottom button row.
	frame.scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
	frame.scrollFrame:SetPoint("TOPLEFT", frame.InsetBg, "TOPLEFT", 4, -34)
	frame.scrollFrame:SetPoint("BOTTOMRIGHT", frame.InsetBg, "BOTTOMRIGHT", -3, 30)
	frame.scrollFrame.ScrollBar:SetPoint("TOPLEFT", frame.scrollFrame, "TOPRIGHT", -20, -22)
	frame.scrollFrame.ScrollBar:SetPoint("BOTTOMRIGHT", frame.scrollFrame, "BOTTOMRIGHT", -15, 22)

	frame.editBox = CreateFrame("EditBox", nil, frame.scrollFrame)
	frame.editBox:SetPoint("TOPLEFT", frame.scrollFrame, 5, -5)
	frame.editBox:SetFontObject(ChatFontNormal)
	frame.editBox:SetWidth(780)
	frame.editBox:SetAutoFocus(true)
	frame.editBox:SetMultiLine(true)
	frame.editBox:SetMaxLetters(99999)
	frame.editBox:SetScript("OnEscapePressed", function() frame:Hide() end)
	frame.scrollFrame:SetScrollChild(frame.editBox)

	local function hideTooltip() GameTooltip:Hide() end

	-- "Select All" button — re-focuses and re-highlights if the user clicked elsewhere.
	local selectAllBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	selectAllBtn:SetSize(100, 22)
	selectAllBtn:SetText("Select All")
	selectAllBtn:SetPoint("BOTTOMLEFT", frame.InsetBg, "BOTTOMLEFT", 4, 4)
	selectAllBtn:SetScript("OnClick", function()
		frame.editBox:SetFocus()
		frame.editBox:HighlightText()
	end)
	selectAllBtn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Select all text, then press Ctrl+C to copy.", nil, nil, nil, nil, true)
		GameTooltip:Show()
	end)
	selectAllBtn:SetScript("OnLeave", hideTooltip)

	-- "Close" button
	local closeBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	closeBtn:SetSize(80, 22)
	closeBtn:SetText("Close")
	closeBtn:SetPoint("BOTTOMRIGHT", frame.InsetBg, "BOTTOMRIGHT", -4, 4)
	closeBtn:SetScript("OnClick", function() frame:Hide() end)

	-- Syncs format button states and checkbox to current session state.
	-- Selected button is locked pushed with white text (1,1,1); others are normal with WoW gold (1,0.82,0).
	frame.updateControls = function()
		for _, btn in ipairs(frame.formatButtons) do
			local selected = btn.value == selectedExportFormat
			btn:SetButtonState(selected and "PUSHED" or "NORMAL", selected)
			btn:GetFontString():SetTextColor(selected and 1 or 1, selected and 1 or 0.82, selected and 1 or 0)
		end
		frame.allCheckbox:SetChecked(selectedExportAll)
	end

	-- Rebuilds export text from tse.recipeData using current format and scope.
	frame.refresh = function()
		if not tse.recipeData then return end
		local data = tse.recipeData

		local recipeText = ""
		local recipeCount = 0
		for _, recipe in ipairs(data.recipes) do
			if selectedExportAll or recipe.isCurrentExpansion then
				if recipe.itemLink then
					recipeText = recipeText .. buildRecipeEntry(recipe.name, recipe.itemLink, selectedExportFormat)
				end
				recipeCount = recipeCount + 1
			end
		end

		if data.skillRank > 0 then
			frame.title:SetText(data.skillName .. " skill " .. data.skillRank .. " - " .. recipeCount .. " recipes")
		end

		local exportText = buildHeader(data.player, data.skillName, data.skillRank, recipeCount, selectedExportFormat) .. recipeText
		frame.editBox:SetText(exportText)
		frame.editBox:HighlightText()
	end

	exportWindow = frame
end
