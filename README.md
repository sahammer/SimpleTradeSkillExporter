# Overview

Simple Trade Skill Exporter is an addon which allows you to export your learned trade skill recipes. It supports all professions and triggered via the tradeskill window or slash commands. You can export your recipes as plain text, Markdown With Wowhead links, or CSV with Wowhead links. Originally inspired by TradeSkillExporter, created with permission from GrumpyOldLisian.

## Supported Versions

- Mists of Pandaria Classic
- Cataclysm Classic
- Wrath of the Lich King Classic
- The Burning Crusade Classic (Anniversary)
- Classic Era (Vanilla)

## Usage

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
