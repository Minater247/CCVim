local Error = {}
local EMPTY_MT = {}
Error.__index = Error
Error.__type = "error"

function Error:new(code, ...)
    return setmetatable({
        code = code,
        params = {...}
    }, Error)
end



local errStrings = {
    [0] = function(params) return "Stop using this error code!!! " .. params[1] end,
    [15] = function(params) return 'Invalid expression: "' .. (params[1] or "") .. '"' end,
    [16] = "Invalid range",
    [81] = "Using <SID> not in a script context",
    [86] = function(params) return "Buffer " .. (params[1] or "?") .. " does not exist" end,
    [32] = "No file name",
    [36] = "Not enough room",
    [37] = "No write since last change (add ! to override)",
    [45] = "'readonly' option is set (add ! to override)",
    [117] = function(params) return "Unknown function: " .. params[1] end,
    [118] = function(params) return "Too many arguments for function: " .. params[1] end,
    [121] = function(params) return "Undefined variable: " .. tostring(params[1]) end,
    [129] = "Function name required",
    [130] = function(params) return "Unknown function: " .. params[1] end,
    [134] = "Cannot move a range of lines into itself",
    [142] = "File not written: Writing is disabled by 'write' option",
    [149] = function(params) return "Sorry, no help for " .. params[1] end,
    [150] = function(params) return "Not a directory: " .. tostring(params[1]) end,
    [154] = function(params) return "Duplicate tag: " .. tostring(params[1]) end,
    [180] = function(params) return "Invalid complete value: " .. tostring(params[1]) end,
    [185] = function(params) return "Cannot find color scheme " .. "'" .. params[1] .. "'" end,
    [189] = function(params) return '"' .. (params[1] or "") .. '" exists (add ! to override)' end,
    [191] = "Argument must be a letter or forward/backward quote",
    [212] = function(params) return "Can't open file for writing" .. (params[1] and (": " .. params[1]) or "") end,
    [327] = "Part of menu-item path is not sub-menu",
    [329] = function(params) return 'No menu "' .. params[1] .. '"' end,
    [331] = "Must not add menu items directly to menu bar",
    [334] = function(params) return "Menu not found: " .. params[1] end,
    [353] = function(params) return "Nothing in register " .. params[1] end,
    [367] = function(params) return 'No such group: "' .. tostring(params[1]) .. '"' end,
    [382] = "Cannot write, 'buftype' option is set",
    [414] = "Group has settings, highlight link ignored",
    [444] = "Cannot close last window",
    [416] = function(params) return "Missing equal sign: " .. params[1] end,
    [461] = function(params) return "Illegal variable name: " .. params[1] end,
    [464] = function(params)
        return "Ambiguous use of user-defined command: " .. params[1] .. " (matches: " .. params[2] .. ")"
    end,
    [467] = "Custom completion requires a function argument",
    [471] = "Argument required",
    [474] = function(params) return "Invalid argument" .. (params[1] and (": " .. params[1]) or "") end,
    [475] = function(params) return "Invalid argument: " .. params[1] end,
    [478] = "Don't panic!",
    [481] = function(params) return "No range allowed" .. (params[1] and (": " .. params[1]) or "") end,
    [484] = function(params) return "Can't open file " .. params[1] end,
    [486] = function(params) return "Pattern not found: " .. (params[1] or "") end,
    [488] = function(params) return "Trailing characters" .. (params[1] and (": " .. params[1]) or "") end,
    [492] = function(params) return "Not an editor command: " .. params[1] end,
    [518] = function(params) return "Unknown option: " .. params[1] end,
    [519] = function(params) return "Option not supported: " .. params[1] end,
    [539] = function(params) return "Illegal character <" .. (params[1] or "") .. ">: " .. (params[2] or "") end,
    [580] = ":endif without :if",
    [581] = ":else without :if",
    [586] = ":continue without :while or :for",
    [587] = ":break without :while or :for",
    [588] = ":endwhile without :while",
    [593] = "Need at least 2 lines",
    [594] = function(params) return "Need at least " .. tostring(params[1] or 12) .. " columns" end,
    [602] = ":endtry without :try",
    [603] = ":catch without :try",
    [606] = ":finally without :try",
    [676] = "No matching autocommands for buftype=acwrite buffer",
    [687] = "Less targets than List items",
    [688] = "More targets than List items",
    [698] = "Variable nested too deep for making a copy",
    [700] = function(params) return "Unknown function: " .. tostring(params[1]) end,
    [703] = "Using a Funcref as a Number",
    [724] = "unable to correctly dump variable with self-referencing container",
    [726] = "Stride is zero",
    [727] = "Start past end",
    [728] = "Using a Dictionary as a Number",
    [730] = "Using a List as a String",
    [739] = function(params)
        return "Cannot create directory " .. tostring(params[1] or "")
            .. (params[2] and (": " .. params[2]) or "")
    end,
    [741] = function(params) return "Value is locked: " .. tostring(params[1]) end,
    [784] = "Cannot close last tab page",
    [745] = "Using a List as a Number",
    [790] = "undojoin is not allowed after undo",
    [804] = "Cannot use '%' with Float",
    [919] = function(params) return "Directory not found in 'packpath': \"pack/*/opt/" .. params[1] .. "\"" end,
    [936] = "Cannot delete the current group",
    [995] = "Cannot modify existing variable",
    [1012] = function(params)
        return "Type mismatch; expected " .. tostring(params[1]) .. " but got " .. tostring(params[2])
    end,
    [1023] = function(params) return "Using a Number as a Bool: " .. tostring(params[1]) end,
    [1030] = function(params) return 'Using a String as a Number: "' .. tostring(params[1]) .. '"' end,
    [1035] = "% requires number arguments",
    [1036] = function(params) return tostring(params[1]) .. " requires number or float arguments" end,
    [1098] = "String, List or Blob required",
    [1135] = function(params) return 'Using a String as a Bool: "' .. tostring(params[1]) .. '"' end,
    [1138] = "Using a Bool as a Number",
    [1174] = function(params) return "String required for argument " .. tostring(params[1]) end,
    [1206] = function(params) return "Dictionary required for argument " .. tostring(params[1] or 1) end,
    [1208] = "-complete used without allowing arguments",
    [1203] = function(params) return "Dot can only be used on a dictionary: " .. tostring(params[1]) end,
    [1225] = function(params)
        return "String, List or Dictionary required for argument " .. tostring(params[1] or 1)
    end,
    [5002] = "Cannot find window number.",
    [5070] = "Character number must not be less than zero",
    [5107] = function(params) return "Error loading lua " .. params[1] end,
    [5108] = function(params) return "Error executing lua " .. (params[1] or "[NULL]") end,
    [5112] = function(params) return "Error while creating lua chunk: " .. params[1] end,
    [5113] = function(params) return "Error while calling lua chunk: " .. params[1] end,
    [5560] = "vim.wait() must not be called in a fast event context",
}

function Error:toString()
    local str = errStrings[self.code]
    if not str then
        LOG_ERROR("INTERNAL ERROR: Unhandled error code: " .. self.code)
    end
    if type(str) == "function" then
        str = str(self.params)
    end
    return "E" .. self.code .. ": " .. str
end

Error.__tostring = Error.toString

setmetatable(Error, {
     __call = function(self, ...) return self:new(...) end
    })

function Error.IsError(obj)
    return (getmetatable(obj) or EMPTY_MT).__type == "error"
end

return Error
