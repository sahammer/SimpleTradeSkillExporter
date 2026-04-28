# Overview

Simple World of Warcraft exporters is a suite of focused addons that make it easy to export your in game data. These tools empower players and guilds to organize their trade skills, rosters and more. Every addon offers multiple export options including Text, CSV and Markdown formatted.

## SimpleTradeSkillExporter

Simple Trade Skill Exporter is an addon which allows you to export your learned trade skill recipes. It supports all professions and triggered via the tradeskill window or slash commands. You can export your recipes as plain text, Markdown With Wowhead links, or CSV with Wowhead links. Originally inspired by TradeSkillExporter, created with permission from GrumpyOldLisian. Part of the *SimpleWowExporters* collection of addons.

### Supported Versions

- Mists of Pandaria Classic
- Cataclysm Classic
- Wrath of the Lich King Classic
- The Burning Crusade Classic (Anniversary)
- Classic Era (Vanilla)

### Usage

Open any trade skill window, then either click the **TSExport** button in the title bar or use `/tsexport`.

The export window opens with format (Text, CSV, Markdown) and scope controls built in — all expansions are shown by default. Uncheck "All expansions" to limit to the current expansion only.

Use the **Select All** button or CTRL-A, then CTRL-C to copy the output and paste it wherever you need it.

### Slash Commands

| Command | Output |
|---------|--------|
| `/tsexport` | Plain text — all expansions |
| `/tsexport current` | Plain text — current expansion only |
| `/tsexport markdown` | Markdown with Wowhead links — all expansions |
| `/tsexport markdown current` | Markdown with Wowhead links — current expansion only |
| `/tsexport csv` | CSV with Wowhead hyperlinks — all expansions |
| `/tsexport csv current` | CSV with Wowhead hyperlinks — current expansion only |
| `/tsexport help` | Show available commands |

---

## SimpleGuildRosterExporter

Simple Guild Roster Exporter allows you to export your guild roster to plain text, CSV, Markdown list, or Markdown table format. Part of the *SimpleWowExporters* collection of addons.

### Supported Versions

- Retail (The War Within / Midnight)
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
