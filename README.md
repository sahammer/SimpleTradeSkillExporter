# Overview

Simple World of Warcraft exporters is a suite of focused addons that make it easy to export your in game data. These tools empower players and guilds to organize their trade skills, rosters and more. Supports Retail and all classic WoW flavors. Every addon offers multiple export options including Text, CSV and Markdown formats.

## SimpleTradeSkillExporter

Simple Trade Skill Exporter is an addon which allows you to export your learned trade skill recipes. It supports all professions and is triggered via the tradeskill window or slash commands. You can export your recipes as plain text, Markdown list, Markdown table, or CSV — with Wowhead links on supported clients. Supports Retail (The War Within) and all classic WoW flavors. Originally inspired by TradeSkillExporter, created with permission from GrumpyOldLisian. Part of the *SimpleWowExporters* collection of addons.

### Supported Versions

- Retail (The War Within)
- Mists of Pandaria Classic
- Cataclysm Classic
- Wrath of the Lich King Classic
- The Burning Crusade Classic (Anniversary)
- Classic Era (Vanilla)

### Usage

Open any trade skill window, then either click the **TSExport** button in the title bar or use `/tsexport`.

The export window opens with format (Text, CSV, MD List, MD Table) and scope controls built in. Check "All expansions" to include all expansions, or leave unchecked to limit to the current expansion only.

Use the **Select All** button or CTRL-A, then CTRL-C to copy the output and paste it wherever you need it.

### Slash Commands

| Command | Output |
|---------|--------|
| `/tsexport` | Plain text — all expansions |
| `/tsexport current` | Plain text — current expansion only |
| `/tsexport markdown` | Markdown list with Wowhead links — all expansions |
| `/tsexport markdown current` | Markdown list with Wowhead links — current expansion only |
| `/tsexport markdown table` | Markdown table with Wowhead links — all expansions |
| `/tsexport markdown table current` | Markdown table with Wowhead links — current expansion only |
| `/tsexport csv` | CSV with Wowhead hyperlinks — all expansions |
| `/tsexport csv current` | CSV with Wowhead hyperlinks — current expansion only |
| `/tsexport help` | Show available commands |

---

## SimpleGuildRosterExporter

Simple Guild Roster Exporter allows you to export your guild roster to plain text, CSV, Markdown list, or Markdown table format. Part of the *SimpleWowExporters* collection of addons.

### Supported Versions

- Retail (The War Within)
- Mists of Pandaria Classic
- Cataclysm Classic
- Wrath of the Lich King Classic
- The Burning Crusade Classic (Anniversary)
- Classic Era (Vanilla)

### Usage

Open the guild frame, then either use `/grexport` or click the export button. On classic clients (Vanilla through Cataclysm) this is a **GRExport** button in the title bar. On MoP Classic and Retail, it appears as an icon tab on the right side panel of the guild frame.

The export window opens with format controls built in — switch between Text, CSV, Markdown List, and Markdown Table without reopening.

Use the **Select All** button or CTRL-A, then CTRL-C to copy the output and paste it wherever you need it.

### Slash Commands

| Command | Output |
|---------|--------|
| `/grexport` | Plain text — all members |
| `/grexport csv` | CSV — all members |
| `/grexport markdown list` | Markdown list — name, level, class |
| `/grexport markdown table` | Markdown table — all fields |
| `/grexport help` | Show available commands |
