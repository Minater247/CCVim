--second attempt at a better syntax highlighter for the vim clone

local parser = {}

local fil = require("/vim/lib/fil")

local output = io.open("/vim/syntax/synt.log", "w")
io.output(output)
local function print(...)
    local args = {...}
    io.write(os.date() .. " LOG: " .. table.concat(args, " "))
    io.write("\n")
    io.flush()
end

function parser.parse(arr, options)
    return arr
end


local args = {...}
print(
    textutils.serialise(
        parser.parse(
            fil.toArr(
                fil.topath(args[1])
            )
        )
    )
)