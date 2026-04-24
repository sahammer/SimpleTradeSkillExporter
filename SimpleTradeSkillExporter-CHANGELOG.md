# 1.3.1
Fixes load message across all classic flavors and defaults export scope to all expansions.

- Fixed loading Lua error on TBC Classic caused by missing GetAddOnMetadata API — load message now omits the version on unsupported clients
- Fixed version not displaying on Anniversary (TBC) by adding support for the retail C_AddOns.GetAddOnMetadata API
- Export window now defaults to all expansions — append `current` to slash commands to filter to current expansion only

# 1.2.1
Adds an in-game TSExport button with inline format and expansion controls, and fixes enchanting expansion filtering.

- Added Export button to the tradeskill window title bar for quick access without slash commands
- Export window now includes inline format (Text, CSV, Markdown) and expansion scope toggle buttons
- Added Select All and Close buttons to the export window
- Fixed enchanting recipes all appearing when filtering by current expansion

# 1.1.0
Adds multi-flavor support for TBC, Wrath, Cataclysm, and Vanilla Classic with per-expansion recipe filtering.

**NOTE:** If you had this addon installed during Cataclysm, `1.0.3` or earlier you may need to re-install the addon. Sorry it was out of date for so long!

- Added support for TBC, Wrath, Cataclysm, and Vanilla Classic
- Recipes now export for the current expansion by default — append `all` to include all expansions
- CSV exports now compatible with Excel and Google Sheets

# 1.0.4
Updates SimpleTradeSkillExporter to support Mists of Pandaria Classic (5.5.x).

- Interface version bumped from `40400` (Cataclysm) to `50503` (MoP Classic 5.5.x)
- Wowhead URLs updated from `/cata/` to `/mop-classic/` for CSV and Markdown exports
- Load notification added on login with a hint to type `/tsexport help`

# 1.0.3
Adds Wago release support and minor display fix.

- Add support for Wago release
- Add space between Addon Title & Version

# 1.0.2
Updates TOC for MoP Classic 1048094 and adds a loading message.

# 1.0.1
Updates TOC for correct Cataclysm version 40400.

# 1.0.0
Initial release with support for exporting recipes as plain text, CSV, and Markdown.