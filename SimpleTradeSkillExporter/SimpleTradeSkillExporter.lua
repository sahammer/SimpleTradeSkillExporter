-- SimpleTradeSkillExporter
-- Author: Hamma
-- Description: Exports trade skill recipes to plain text, CSV, or Markdown format.
--              Supports all classic WoW flavors (Vanilla, TBC, Wrath, Cata, MoP).
--              Use /tsexport or the Export button on the tradeskill window.

local addonName, tse = ...
local SWE = tse.SWE  -- loaded by SimpleWowExportersLib.lua via TOC

local wowheadUrls = {
	[WOW_PROJECT_MISTS_CLASSIC]           = "https://wowhead.com/mop-classic/",
	[WOW_PROJECT_CATACLYSM_CLASSIC]       = "https://wowhead.com/cata/",
	[WOW_PROJECT_WRATH_CLASSIC]           = "https://wowhead.com/wotlk/",
	[WOW_PROJECT_BURNING_CRUSADE_CLASSIC] = "https://wowhead.com/tbc/",
	[WOW_PROJECT_CLASSIC]                 = "https://wowhead.com/classic/",
}
tse.wowheadBase = wowheadUrls[WOW_PROJECT_ID]

local expansionItemIdFloors = {
	[WOW_PROJECT_MISTS_CLASSIC]           = 71000,
	[WOW_PROJECT_CATACLYSM_CLASSIC]       = 52000,
	[WOW_PROJECT_WRATH_CLASSIC]           = 35000,
	[WOW_PROJECT_BURNING_CRUSADE_CLASSIC] = 24000,
	[WOW_PROJECT_CLASSIC]                 = nil,
}
tse.expansionItemIdFloor = expansionItemIdFloors[WOW_PROJECT_ID]

local exportWindow

local validFormats = { text = true, csv = true, markdown = true }

-- Examples: "csv all" -> ("csv", true), "" -> ("text", false), "foo" -> ("text", false) + warning
-- Unknown format values are normalised to "text" with a warning printed to chat.
local function parseCommand(msg)
	local parts = {}
	for part in msg:gmatch("%S+") do table.insert(parts, part) end

	local exportAll = parts[#parts] == "all"
	if exportAll then table.remove(parts, #parts) end

	local format = parts[1] or "text"
	if not validFormats[format] then
		print("|cffFF0000[TSE]:|r Unknown format '" .. format .. "', defaulting to text.")
		format = "text"
	end

	return format, exportAll
end

local function getCraftedOutputId(index)
	local itemLink = GetTradeSkillItemLink(index)
	if not itemLink then return nil end
	local id = itemLink:match("item:(%d+)") or itemLink:match("enchant:(%d+)")
	return id and tonumber(id) or nil
end

local function isCurrentExpansionRecipe(index)
	if not tse.expansionItemIdFloor then return true end
	local outputId = getCraftedOutputId(index)
	if outputId == nil then return true end
	return outputId >= tse.expansionItemIdFloor
end

local function getPlayerInfo()
	local name   = UnitName("player")
	local race   = UnitRace("player")
	local class  = UnitClass("player")
	local level  = UnitLevel("player")
	local guild  = GetGuildInfo("player") or "-"
	local server = GetRealmName()
	return { name = name, race = race, class = class, level = level, guild = guild, server = server }
end

local function buildHeader(player, skillName, rank, recipeCount, exportType)
	if exportType == "markdown" then
		local h =
			"**Player:** " .. player.name .. ", Level " .. player.level .. " " .. player.race .. " " .. player.class .. "  \n" ..
			"**Guild:** "   .. player.guild  .. "  \n" ..
			"**Server:** "  .. player.server .. "  \n"
		if rank > 0 then
			h = h .. "**" .. skillName .. ":** Skill " .. rank .. ", " .. recipeCount .. " total recipes  \n"
		end
		return h .. "\n"
	elseif exportType == "csv" then
		return ""
	else
		local h =
			"Player: " .. player.name .. ", Level " .. player.level .. " " .. player.race .. " " .. player.class .. "  \n" ..
			"Guild: "   .. player.guild  .. "  \n" ..
			"Server: "  .. player.server .. "  \n"
		if rank > 0 then
			h = h .. skillName .. " skill " .. rank .. ", " .. recipeCount .. " total recipes  \n"
		end
		return h .. "---------------------\n"
	end
end

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

local function getItemLink(index)
	local itemLink, itemId

	itemLink = GetTradeSkillItemLink(index)
	if itemLink then
		itemId = itemLink:match("item:(%d+)") or itemLink:match("enchant:(%d+)")
		if itemId then return "item=" .. tonumber(itemId) end
	end

	itemLink = GetTradeSkillRecipeLink(index)
	if itemLink then
		itemId = itemLink:match("item:(%d+)") or itemLink:match("enchant:(%d+)")
		if itemId then
			return "spell=" .. tonumber(itemId)
		else
			print("|cffFF0000[TSE]: Unable to process entry " .. index)
			if itemLink then print(itemLink:gsub('\124', '\124\124')) end
			return nil
		end
	end

	return nil
end

local function captureRecipeData()
	local skillName, skillRank = GetTradeSkillLine()
	if skillRank == 0 then return false end

	local recipes = {}
	for i = 1, GetNumTradeSkills() do
		local name, entryType = GetTradeSkillInfo(i)
		if name and entryType ~= "header" then
			table.insert(recipes, {
				name               = name,
				itemLink           = getItemLink(i),
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

-- onRefresh callback passed to SWE.CreateExportWindow.
-- Builds the full export text from tse.recipeData for the given format and scope.
local function buildExportText(format, scope)
	tse.lastFormat = format
	tse.lastScope  = scope
	if not tse.recipeData then return "", "" end
	local data = tse.recipeData

	local lines = {}
	local count = 0
	for _, recipe in ipairs(data.recipes) do
		if scope or recipe.isCurrentExpansion then
			if recipe.itemLink then
				local url = tse.wowheadBase and (tse.wowheadBase .. recipe.itemLink) or nil
				lines[#lines + 1] = SWE.RenderRow(format, { { label = recipe.name, url = url } })
				count = count + 1
			end
		end
	end

	local header = buildHeader(data.player, data.skillName, data.skillRank, count, format)
	local title  = data.skillName .. " skill " .. data.skillRank .. " - " .. count .. " recipes"
	return header .. table.concat(lines), title
end

local function runExport(exportType, exportAll)
	if (exportType == "csv" or exportType == "markdown") and not tse.wowheadBase then
		print("\124cffFF0000Error:\124r CSV and Markdown exports are not supported on this version of WoW.")
		return
	end

	if not captureRecipeData() then
		print("\124cffFF0000Error:\124r Must open a tradeskill window. Type /tsexport help for more information.")
		return
	end

	if not exportWindow then
		exportWindow = SWE.CreateExportWindow({
			buttons = {
				{ label = "Text",     value = "text" },
				{ label = "CSV",      value = "csv",      disabled = not tse.wowheadBase },
				{ label = "Markdown", value = "markdown",  disabled = not tse.wowheadBase },
			},
			defaultFormat = "text",
			hasScope      = tse.expansionItemIdFloor ~= nil,
			onRefresh     = buildExportText,
		})
	end

	tse.lastFormat = exportType
	tse.lastScope  = exportAll
	exportWindow:Open(exportType, exportAll)
end

local function attachTradeSkillButton()
	if tse.tradeSkillButton then return end

	local button = CreateFrame("Button", nil, TradeSkillFrame, "UIPanelButtonTemplate")
	button:SetSize(72, 18)
	button:SetText("TSExport")
	button:SetPoint("LEFT", TradeSkillFramePortrait, "RIGHT", 9, 12)
	button:SetScript("OnClick", function()
		runExport(tse.lastFormat or "text", tse.lastScope or false)
	end)

	tse.tradeSkillButton = button
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("TRADE_SKILL_SHOW")
eventFrame:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" and arg1 == addonName then
		if not tse.SWE then
			print("\124cffFF0000[TSE] Error:\124r SimpleWowExportersLib failed to load. Ensure SimpleWowExportersLib.lua is in the addon folder.")
			self:UnregisterEvent("ADDON_LOADED")
			self:UnregisterEvent("TRADE_SKILL_SHOW")
			return
		end
		local getMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
		local version = getMetadata and getMetadata(addonName, "Version")
		local versionStr = version and " v" .. version or ""
		print("\124cff00FF00SimpleTradeSkillExporter" .. versionStr .. "\124r loaded. Type \124cff00FF00/tsexport help\124r for usage.")
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
