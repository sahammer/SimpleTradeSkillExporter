-- SimpleGuildRosterExporter
-- Author: Hamma
-- Description: Exports guild roster data to plain text, CSV, Markdown list, or Markdown table format.
--              Supports all classic WoW flavors (Vanilla, TBC, Wrath, Cata, MoP) and Retail.
--              Use /grexport or the GRExport button on the guild frame.

local addonName, gre = ...
local SWE = gre.SWE  -- loaded by SimpleWowExportersLib.lua via TOC

local exportWindow
-- Holds the requested export format across an async GuildRoster() request.
-- Set in runExport when roster data is unavailable; cleared after GUILD_ROSTER_UPDATE fires.
local pendingFormat = nil

-- GuildRoster() is the classic API; C_GuildInfo.GuildRoster() is the retail-based client API (e.g. Anniversary)
local requestRoster  = (C_GuildInfo and C_GuildInfo.GuildRoster) or GuildRoster
-- GetAddOnMetadata lives under C_AddOns on retail-based clients (Anniversary, MoP)
local getAddonMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata

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

-- Returns "Online" for online members, or a human-readable offline duration.
-- Shows two levels of granularity (e.g. "2mo 5d", "3d 14h") suppressing
-- smaller units when larger ones are present.
local function formatLastOnline(isOnline, index)
	if isOnline then return "Online" end
	if GetGuildRosterLastOnline then
		local years, months, days, hours = GetGuildRosterLastOnline(index)
		if years  > 0 then
			return months > 0 and years .. "y " .. months .. "mo ago" or years .. "y ago"
		end
		if months > 0 then
			return days > 0 and months .. "mo " .. days .. "d ago" or months .. "mo ago"
		end
		if days   > 0 then
			return hours > 0 and days .. "d " .. hours .. "h ago" or days .. "d ago"
		end
		if hours  > 0 then return hours .. "h ago" end
		return "< 1h ago"
	end
	return "Offline"
end

-- Strips duplicate realm suffixes from names (Blizzard bug: "Player-Realm-Realm")
local function cleanName(name)
	local player, realm = name:match("^(.+)-(.+)$")
	if player and realm then
		local innerRealm = player:match("^.+-(.+)$")
		if innerRealm == realm then
			return player
		end
	end
	return name
end

local function captureRosterData()
	local guildName = GetGuildInfo("player")
	if not guildName then return false end

	local totalMembers = GetNumGuildMembers()
	if totalMembers == 0 then return false end
	local members = {}
	for i = 1, totalMembers do
		-- GetGuildRosterInfo returns: name, rankName, rankIndex, level, class, zone, note, officerNote, isOnline, ...
		local name, rankName, _, level, classDisplayName, _, _, _, isOnline = GetGuildRosterInfo(i)
		if name and name ~= "" then
			table.insert(members, {
				name       = cleanName(name),
				class      = classDisplayName or "Unknown",
				level      = level or 0,
				rank       = rankName or "",
				lastOnline = formatLastOnline(isOnline, i),
				isOnline   = isOnline and true or false,
			})
		end
	end

	table.sort(members, function(a, b) return a.name < b.name end)

	gre.rosterData = {
		guildName = guildName,
		server    = GetRealmName(),
		members   = members,
	}

	return true
end

local function buildHeader(data, memberCount, format)
	if format == "csv" then
		return ""
	elseif format == "markdown-table" or format == "markdown-list" then
		return "**Guild:** " .. data.guildName .. "  \n" ..
		       "**Server:** " .. data.server .. "  \n" ..
		       "**Members:** " .. memberCount .. "  \n\n"
	else
		return "Guild: " .. data.guildName .. "\n" ..
		       "Server: " .. data.server .. "\n" ..
		       "Members: " .. memberCount .. "\n\n"
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

local columns = { "Name", "Level", "Class", "Rank", "Last Online" }

local function formatMemberRow(format, libRendererFormat, member)
	if format == "markdown-list" then
		local entry = member.name .. ", Level " .. member.level .. " " .. member.class
		return SWE.RenderRow(libRendererFormat, { entry })
	elseif format == "text" then
		local entry = member.name .. " | " .. member.level .. " " .. member.class .. " | " .. member.rank .. " | " .. member.lastOnline
		return SWE.RenderRow(libRendererFormat, { entry })
	else
		return SWE.RenderRow(libRendererFormat, {
			member.name,
			tostring(member.level),
			member.class,
			member.rank,
			member.lastOnline,
		})
	end
end

local function computeMemberCount(lines, format)
	-- csv and markdown-table prepend a header row that must not be counted as a member
	local hasHeaderRow = format == "csv" or format == "markdown-table"
	return hasHeaderRow and (#lines - 1) or #lines
end

-- onRefresh callback passed to SWE.CreateExportWindow.
-- Builds the full export text from gre.rosterData for the given format.
local function buildExportText(format, includeOffline)
	gre.lastFormat = format
	if not gre.rosterData then return "", "" end
	local data = gre.rosterData
	local libRendererFormat = libFormat(format)

	local lines = {}

	if format == "csv" or format == "markdown-table" then
		lines[#lines + 1] = SWE.RenderHeader(libRendererFormat, columns)
	end

	for _, member in ipairs(data.members) do
		if includeOffline or member.isOnline then
			lines[#lines + 1] = formatMemberRow(format, libRendererFormat, member)
		end
	end

	local count  = computeMemberCount(lines, format)
	local header = buildHeader(data, count, format)
	local title  = data.guildName .. " — " .. count .. " members"
	return header .. table.concat(lines), title
end

local function runExport(exportType)
	if not GetGuildInfo("player") then
		print("\124cffFF0000Error:\124r You are not in a guild.")
		return
	end

	if not exportWindow then
		exportWindow = SWE.CreateExportWindow({
			buttons = {
				{ label = "Text",           value = "text",           width = 60  },
				{ label = "CSV",            value = "csv",            width = 60  },
				{ label = "Markdown List",  value = "markdown-list",  width = 115 },
				{ label = "Markdown Table", value = "markdown-table", width = 115 },
			},
			defaultFormat = "text",
			hasScope      = true,
			scopeLabel    = "Include offline",
			onRefresh     = buildExportText,
		})
	end

	gre.lastFormat = exportType

	-- Try to capture immediately in case data is already cached.
	-- If data unavailable, fall back to async request.
	if captureRosterData() then
		exportWindow:Open(exportType, true)
	elseif requestRoster then
		pendingFormat = exportType
		requestRoster()
	else
		print("\124cffFF0000Error:\124r Unable to request guild roster on this client.")
	end
end

-- Forward declaration required because hookFrameOnShow references attachGuildButton
-- before it is defined below.
local attachGuildButton

-- Hooks attachGuildButton onto targetFrame's OnShow if not already hooked.
-- flagKey is a gre table key used to track whether the hook has been applied.
local function hookFrameOnShow(targetFrame, flagKey)
	if targetFrame and not gre[flagKey] then
		gre[flagKey] = true
		targetFrame:HookScript("OnShow", attachGuildButton)
	end
end

attachGuildButton = function()
	if gre.guildButton then return end
	-- GetBuildInfo() field 4 is the numeric interface version (e.g. 50400 for MoP 5.4, 120005 for Retail)
	-- MoP Classic: 50000–59999. Retail: 100000+. All others are earlier classic flavors.
	local buildVersion = select(4, GetBuildInfo())
	local isMopOrRetail = (buildVersion >= 50000 and buildVersion < 60000) or buildVersion >= 100000
	local frame, applyButtonPosition
	if isMopOrRetail and CommunitiesFrame and CommunitiesFrame.GuildInfoTab then
		-- MoP Classic (50xxx) and Retail (100xxx+): icon tab on right side below GRM's tab or Blizzard's GuildInfoTab
		frame = CommunitiesFrame
		applyButtonPosition = function(btn)
			btn:SetPoint("TOP", CommunitiesFrame.GuildInfoTab, "BOTTOM", 0, -64)
		end
	elseif CommunitiesFrame and CommunitiesFrame.portrait and CommunitiesFrame:IsShown() then
		-- Fallback: CommunitiesFrame with portrait but no GuildInfoTab (future-proofing)
		frame = CommunitiesFrame
		applyButtonPosition = function(btn) btn:SetPoint("LEFT", CommunitiesFrame.portrait, "RIGHT", 9, 12) end
	elseif GuildFrame and GuildFrame:IsShown() then
		if GuildFramePortrait then
			-- Wrath/Cata/Vanilla: classic guild frame with portrait
			frame = GuildFrame
			applyButtonPosition = function(btn) btn:SetPoint("LEFT", GuildFramePortrait, "RIGHT", 9, 12) end
		else
			-- TBC-style guild frame: no portrait, position next to "Show Offline Members"
			frame = GuildFrame
			applyButtonPosition = function(btn) btn:SetPoint("TOPLEFT", GuildFrame, "TOPLEFT", 50, -27) end
		end
	else
		-- Frame not shown yet — hook for when it opens
		hookFrameOnShow(CommunitiesFrame, "communityHooked")
		hookFrameOnShow(GuildFrame, "guildFrameHooked")
		return
	end

	local isCommunitiesTabLayout = isMopOrRetail and CommunitiesFrame and CommunitiesFrame.GuildInfoTab

	local button = CreateFrame("Button", nil, frame, isCommunitiesTabLayout and "UIPanelButtonGrayTemplate" or "UIPanelButtonTemplate")
	if isCommunitiesTabLayout then
		button:SetSize(44, 44)
		local icon = button:CreateTexture(nil, "OVERLAY")
		-- MoP Classic is 50xxx; Retail is 100xxx+ — adjusts icon size and centering offset to match each client's tab style
		local isMopClassic = buildVersion < 100000
		local iconSize  = isMopClassic and 36 or 33
		local offsetX   = isMopClassic and 0 or 2.5
		local offsetY   = isMopClassic and 0 or -1.5
		icon:SetPoint("CENTER", button, "CENTER", offsetX, offsetY)
		icon:SetSize(iconSize, iconSize)
		icon:SetTexture("Interface\\Icons\\inv_misc_note_05")
		button:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
			GameTooltip:AddLine("SimpleGuildRosterExporter")
			GameTooltip:AddLine("/grexport to export", 1, 1, 1)
			GameTooltip:Show()
		end)
		button:SetScript("OnLeave", function() GameTooltip:Hide() end)
	else
		button:SetSize(72, 18)
		button:SetText("GRExport")
	end
	applyButtonPosition(button)
	button:SetScript("OnClick", function()
		runExport(gre.lastFormat or "text")
	end)

	gre.guildButton = button
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("GUILD_ROSTER_UPDATE")
eventFrame:RegisterEvent("PLAYER_GUILD_UPDATE")
eventFrame:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" and arg1 == addonName then
		if not gre.SWE then
			print("\124cffFF0000[GRE] Error:\124r SimpleWowExportersLib failed to load. Ensure SimpleWowExportersLib.lua is in the addon folder.")
			self:UnregisterAllEvents()
			return
		end
		local version = getAddonMetadata and getAddonMetadata(addonName, "Version")
		SWE.RegisterAddon("SimpleGuildRosterExporter", version, "/grexport help")
		self:UnregisterEvent("ADDON_LOADED")
	elseif event == "GUILD_ROSTER_UPDATE" or event == "PLAYER_GUILD_UPDATE" then
		attachGuildButton()
		if event == "GUILD_ROSTER_UPDATE" and pendingFormat then
			local captured = captureRosterData()
			if captured and exportWindow and gre.rosterData then
				exportWindow:Open(pendingFormat, true)
			elseif not captured then
				print("\124cffFF0000Error:\124r Unable to capture guild roster data.")
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
