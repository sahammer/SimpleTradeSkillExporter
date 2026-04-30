# 1.0.1
Fixes plain text header formatting and export window scope preservation.

- Fixed plain text export header using markdown-style line breaks — now uses standard line endings
- Fixed export window losing the selected scope when switching formats
- Fixed export not triggering when guild roster data was unavailable at the time of the request on some clients

# 1.0.0
Initial release of SimpleGuildRosterExporter.

- Export guild roster data to plain text, CSV, Markdown list, or Markdown table
- Includes all members (online and offline) with accurate last online duration
- Toggle offline members via the "Include offline" checkbox in the export window
- GRExport button on the guild frame for classic clients; icon tab on the right side panel for MoP Classic and Retail
- /grexport slash command with format options
- Combined load message with other Simple WoW Exporters addons
- /swexport help lists commands across all loaded Simple WoW Exporters addons
