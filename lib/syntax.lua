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
    local currentstate = "normal"
    for i=1,#arr do

        --split the string at punctuation
        local words = {}
        local word = ""
        for j=1,#arr[i] do
            if arr[i]:sub(j, j):match("%W") then
                if word ~= "" then
                    words[#words+1] = word
                    print("got word: "..word)
                end
                words[#words+1] = arr[i]:sub(j, j)
                if arr[i]:sub(j, j) ~= " " then
                    print("split at: "..arr[i]:sub(j, j))
                end
                word = ""
            else
                word = word .. arr[i]:sub(j, j)
            end
        end
        if word ~= "" then
            words[#words+1] = word
            print("got word: "..word)
        end


    end
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