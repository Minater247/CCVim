local Sign = {}

--[[
    Each entry is:
    - icon (unused)
    - linehl: highlight for the whole line of the sign
    - priority (unused for now)
    - numhl: highlight fo the line number of the sign
    - text: text to display when no GUI
    - texthl: hl for text above
    - culhl: cursorline hl override
]]
local signs = {}

function Sign.define(name, opts)
    signs[name] = opts
end

-- todo: returning internal values is bad
function Sign.getdefined(name)
    return signs[name] and {signs[name]} or signs
end

function Sign.undefine(name)
    if name == nil then
        signs = {}
    else
        if not signs[name] then
            return -1
        end
        signs[name] = nil
    end
    return 0
end

function Sign.place(id, group, name, buf, opts)

end

function Sign.unplace(group, opts)

end


return Sign