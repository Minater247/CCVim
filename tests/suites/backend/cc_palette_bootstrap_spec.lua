return {
    id = "backend.cc_palette_bootstrap",
    description = "Bootstraps the CC backend palette from the current terminal palette instead of hardcoded defaults.", -- luacheck: ignore 631

    run = function(ctx)
        local Assert = ctx.assert

        local function slot_from_palette_index(index)
            index = tonumber(index)
            if index == 0 then
                return index
            end
            if (index == 1) or (index > 0 and math.floor(index) == index and index % 2 == 0) then
                local slot = 0
                local value = index
                while value > 1 do
                    value = value / 2
                    slot = slot + 1
                end
                return slot
            end
            if index >= 0 and index <= 15 and math.floor(index) == index then
                return index
            end

            local slot = 0
            local value = index
            while value > 1 do
                value = value / 2
                slot = slot + 1
            end
            return slot
        end

        local function pack_expected(channel)
            return math.floor(channel * 255 + 0.5)
        end

        local palette = {}
        for slot = 0, 15 do
            palette[slot] = {
                slot / 15,
                (15 - slot) / 15,
                ((slot * 3) % 16) / 15,
            }
        end

        local term = {
            getPaletteColor = function(mask)
                local rgb = palette[slot_from_palette_index(mask)]
                return rgb[1], rgb[2], rgb[3]
            end,
            setPaletteColor = function(mask, r, g, b)
                palette[slot_from_palette_index(mask)] = { r, g, b }
            end,
        }

        local env = setmetatable({
            term = term,
            window = {
                create = function()
                    return {
                        setVisible = function()
                        end,
                        setPaletteColor = function()
                        end,
                        blit = function()
                        end,
                        setCursorPos = function()
                        end,
                    }
                end,
            },
            shell = {
                dir = function()
                    return ""
                end,
                setDir = function()
                end,
                resolve = function(path)
                    return path
                end,
                getRunningProgram = function()
                    return "nvim.lua"
                end,
            },
            os = {
                pullEvent = function()
                end,
                startTimer = function()
                    return 1
                end,
                cancelTimer = function()
                end,
                epoch = function()
                    return 0
                end,
            },
            keys = {},
            fs = {},
        }, { __index = _G })

        local chunk, err = loadfile((rawget(_G, "__CCVIM_TEST_ROOT") or ".") .. "/lib/backend/cc.lua", "t", env)
        Assert.truthy("cc backend chunk loads", chunk ~= nil, err)

        local CC = chunk()

        for slot = 0, 15 do
            local want = palette[slot]
            local r, g, b = CC.get_palette_slot(slot)
            Assert.eq("slot " .. slot .. " red", r, pack_expected(want[1]))
            Assert.eq("slot " .. slot .. " green", g, pack_expected(want[2]))
            Assert.eq("slot " .. slot .. " blue", b, pack_expected(want[3]))
        end
    end,
}
