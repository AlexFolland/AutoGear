---@class AutoGearAddon
---@field public Localization table<string, string> Table used for localization.

---Returns info for an item
---@param itemId string|number
---@return string, string, number, number, number, string, string, number, string, string, number
function GetItemInfo(itemId) end

---Returns info for the current client build.
---
---version, build, date, tocversion
---
---Example:
---```/dump GetBuildInfo() -- "9.0.2", "36665", "Nov 17 2020", 90002```
---@return string,string,string,number
function GetBuildInfo() end
