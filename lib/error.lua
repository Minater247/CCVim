local Error = {}
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
    [16] = "Invalid range",
    [81] = function(params) return params[1] or "Using <SID> not in a script context" end,
    [86] = function(params) return "Buffer " .. (params[1] or "?") .. " does not exist" end,
    [32] = "No file name",
    [36] = "Not enough room",
    [37] = "No write since last change (add ! to override)",
    [45] = "'readonly' option is set (add ! to override)",
    [117] = function(params) return "Unknown Function: " .. params[1] end,
    [118] = function(params) return "Too many or invalid arguments for: " .. (params[1] or "call") end,
    [134] = "Cannot move a range of lines into itself",
    [142] = "File not written: Writing is disabled by 'write' option",
    [149] = function(params) return "Sorry, no help for " .. params[1] end,
    [189] = function(params) return (params[1] or "File") .. " exists (add ! to override)" end,
    [191] = "Argument must be a letter or forward/backward quote",
    [212] = "Cannot open file for writing",
    [329] = function(params) return 'No menu "' .. params[1] .. '"' end,
    [334] = function(params) return "Menu not found: " .. params[1] end,
    [353] = function(params) return "Nothing in register " .. params[1] end,
    [382] = "Cannot write, 'buftype' option is set",
    [414] = "group has settings, highlight link ignored",
    [444] = "Cannot close last window",
    [416] = function(params) return "Missing equal sign: " .. params[1] end,
    [461] = function(params) return "Illegal variable name: " .. params[1] end,
    [464] = function(params)
        return "Ambiguous use of user-defined command: " .. params[1] .. " (matches: " .. params[2] .. ")"
    end,
    [471] = "Argument required",
    [474] = function(params) return "Invalid argument" .. (params[1] and (": " .. params[1]) or "") end,
    [475] = function(params) return "Invalid argument: " .. params[1] end,
    [478] = "Don't panic!",
    [481] = function(params) return "No range allowed: " .. (params[1] or "") end,
    [484] = function(params) return "Can't open file " .. params[1] end,
    [486] = function(params) return "Pattern not found: " .. (params[1] or "") end,
    [488] = function(params) return "Trailing characters: " .. (params[1] or "") end,
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
    [698] = "Variable nested too deep for making a copy",
    [703] = "Using a Funcref as a Number",
    [724] = "Cannot use deepcopy() with a cyclic reference when {noref} is 1",
    [728] = "Using a Dictionary as a Number",
    [739] = function(params) return "Cannot create directory: " .. tostring(params[1] or "") end,
    [745] = "Using a List as a Number",
    [790] = "undojoin is not allowed after undo",
    [919] = function(params) return "Directory not found in 'packpath': " .. (params[1] or "") end,
    [1098] = "String, List or Blob required",
    [1206] = function(params) return "Dictionary required for argument " .. tostring(params[1] or 1) end,
    [1225] = function(params)
        return "String, List or Dictionary required for argument " .. tostring(params[1] or 1)
    end,
    [5002] = "Cannot find window number.",
    [5107] = function(params) return "Error loading lua " .. params[1] end,
    [5108] = function(params) return "Error executing lua " .. (params[1] or "[NULL]") end,
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

setmetatable(Error, {
     __call = function(self, ...) return self:new(...) end
    })

function Error.IsError(obj)
    local mt = getmetatable(obj)
    if mt and mt.__type then
        return mt.__type == "error"
    end
    return false
end

return Error
