-- SimpleGuildRosterExporter
-- Author: Hamma
-- Description: Exports guild roster data to plain text, CSV, Markdown list, or Markdown table format.
--              Supports all classic WoW flavors (Vanilla, TBC, Wrath, Cata, MoP).
--              Use /grexport or the GRExport button on the guild frame.

local addonName, gre = ...
local SWE = gre.SWE  -- loaded by SimpleWowExportersLib.lua via TOC

local exportWindow
local pendingFormat = nil

-- GuildRoster() is the classic API; C_GuildInfo.GuildRoster() is the retail-based client API (e.g. Anniversary)
local requestRoster = (C_GuildInfo and C_GuildInfo.GuildRoster) or GuildRoster

local validFormats = { text = true, csv = true, ["markdown-list"] = true, ["markdown-table"] = true }

-- Translates GRE format values to the lib's internal format keys.
local function libFormat(format)
	if format == "markdown-list"  then return "markdown" end
	if format == "markdown-table" then return "md-table" end
	return format
end

-- Examples: "csv" -> "csv", "markdown list" -> "markdown-list", "" -> "text", "foo" -> "text" + warning
local function parseCommand(msg)
	local parts = {}
	for part in msg:gmatch("%S+") do table.insert(parts, part) end

	if parts[1] == "markdown" then
		if parts[2] == "table" then return "markdown-table" end
		return "markdown-list"
	end

	local format = parts[1] or "text"
	if not validFormats[format] then
		print("|cffFF0000[GRE]:|r Unknown format '" .. format .. "', defaulting to text.")
		format = "text"
	end

	return format
end

-- Returns "Online" for online members, "Offline" for offline members.
local function formatLastOnline(isOnline)
	return isOnline and "Online" or "Offline"
end

local function captureRosterData()
	local guildName = GetGuildInfo("player")
	if not guildName then return false end

	local totalMembers = GetNumGuildMembers()
	local members = {}
	for i = 1, totalMembers do
		local name, rankName, _, level, classDisplayName, _, _, _, isOnline = GetGuildRosterInfo(i)
		if name then
			table.insert(members, {
				name       = name,
				class      = classDisplayName,
				level      = level,
				rank       = rankName,
				lastOnline = formatLastOnline(isOnline),
			})
		end
	end

	gre.rosterData = {
		guildName = guildName,
		server    = GetRealmName(),
		members   = members,
	}

	return true
end

local function buildHeader(data, memberCount, format)
	if format == "csv" or format == "markdown-table" then
		return ""
	elseif format == "markdown-list" then
		return "**Guild:** " .. data.guildName .. " — " .. data.server .. "  \n" ..
		       "**Members:** " .. memberCount .. "  \n\n"
	else
		return "Guild: " .. data.guildName .. " — " .. data.server .. "  \n" ..
		       "Members: " .. memberCount .. "  \n" ..
		       "---------------------\n"
	end
end

local function printHelp()
	print("\124cff00FF00GRE:\124r \124cff00FF00S\124rimple \124cff00FF00G\124ruild \124cff00FF00R\124roster \124cff00FF00E\124rxporter - Help")
	print("\124cff00FF00GRE:\124r Type '/grexport help' to show this message")
	print("\124cff00FF00GRE:\124r '/grexport' - plain text list")
	print("\124cff00FF00GRE:\124r '/grexport csv' - Comma Separated Value list")
	print("\124cff00FF00GRE:\124r '/grexport markdown list' - Markdown list (name, level, class)")
	print("\124cff00FF00GRE:\124r '/grexport markdown table' - Markdown table (all fields)")
end

local columns = { "Name", "Class", "Level", "Rank", "Last Online" }

-- onRefresh callback passed to SWE.CreateExportWindow.
-- Builds the full export text from gre.rosterData for the given format.
local function buildExportText(format, _scope)
	gre.lastFormat = format
	if not gre.rosterData then return "", "" end
	local data = gre.rosterData
	local lf   = libFormat(format)

	local lines = {}

	if format == "csv" or format == "markdown-table" then
		lines[#lines + 1] = SWE.RenderHeader(lf, columns)
	end

	for _, member in ipairs(data.members) do
		if format == "markdown-list" then
			local entry = member.name .. ", Level " .. member.level .. " " .. member.class
			lines[#lines + 1] = SWE.RenderRow(lf, { entry })
		else
			lines[#lines + 1] = SWE.RenderRow(lf, {
				member.name,
				member.class,
				tostring(member.level),
				member.rank,
				member.lastOnline,
			})
		end
	end

	local count  = #data.members
	local header = buildHeader(data, count, format)
	local title  = data.guildName .. " — " .. count .. " members"
	return header .. table.concat(lines), title
end

local function runExport(exportType)
	if not exportWindow then
		exportWindow = SWE.CreateExportWindow({
			buttons = {
				{ label = "Text",     value = "text" },
				{ label = "CSV",      value = "csv" },
				{ label = "MD List",  value = "markdown-list" },
				{ label = "MD Table", value = "markdown-table" },
			},
			defaultFormat = "text",
			hasScope      = false,
			onRefresh     = buildExportText,
		})
	end

	gre.lastFormat = exportType
	pendingFormat  = exportType
	requestRoster()
end

local function attachGuildButton()
	if gre.guildButton then return end
	if not GuildFrame or not GuildFramePortrait then return end

	local button = CreateFrame("Button", nil, GuildFrame, "UIPanelButtonTemplate")
	button:SetSize(72, 18)
	button:SetText("GRExport")
	button:SetPoint("LEFT", GuildFramePortrait, "RIGHT", 9, 12)
	button:SetScript("OnClick", function()
		runExport(gre.lastFormat or "text")
	end)

	gre.guildButton = button
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("GUILD_ROSTER_UPDATE")
eventFrame:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" and arg1 == addonName then
		if not gre.SWE then
			print("\124cffFF0000[GRE] Error:\124r SimpleWowExportersLib failed to load. Ensure SimpleWowExportersLib.lua is in the addon folder.")
			self:UnregisterEvent("ADDON_LOADED")
			self:UnregisterEvent("GUILD_ROSTER_UPDATE")
			return
		end
		local getMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
		local version     = getMetadata and getMetadata(addonName, "Version")
		local versionStr  = version and " v" .. version or ""
		print("\124cff00FF00SimpleGuildRosterExporter" .. versionStr .. "\124r loaded. Type \124cff00FF00/grexport help\124r for usage.")
		self:UnregisterEvent("ADDON_LOADED")
	elseif event == "GUILD_ROSTER_UPDATE" then
		attachGuildButton()
		if pendingFormat then
			captureRosterData()
			if exportWindow and gre.rosterData then
				exportWindow:Open(pendingFormat, false)
			end
			pendingFormat = nil
		end
	end
end)

SLASH_SIMPLEGUILDROSTEREXPORTER1 = "/grexport"
SlashCmdList["SIMPLEGUILDROSTEREXPORTER"] = function(msg)
	if msg == "help" then
		printHelp()
		return
	end
	local exportType = parseCommand(msg)
	runExport(exportType)
end
