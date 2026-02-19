local MockEnv = require("vim.tests.test_mocks")

local mock = MockEnv.setup()
local Options = mock.loadModule("vim.lib.options")
_G.options = Options
_G.screen = { width = 80, height = 24 }

local FrameTree = mock.loadModule("vim.lib.frame")

local function fail(msg)
    error("FAIL frametree fuzzer: " .. msg)
end

local function assert_true(cond, msg)
    if not cond then
        fail(msg)
    end
end

local function is_int(n)
    return n == math.floor(n)
end

local function collect_leaves(node, out)
    out = out or {}
    if not node.split_type then
        out[#out + 1] = node
        return out
    end
    collect_leaves(node.children[1], out)
    collect_leaves(node.children[2], out)
    return out
end

local function snapshot_tree(node)
    local snap = {
        split = node.split_type,
        width = node.width,
        height = node.height,
        id = node.window and node.window.winnr or 0,
    }
    if node.children then
        snap.a = snapshot_tree(node.children[1])
        snap.b = snapshot_tree(node.children[2])
    end
    return snap
end

local function same_snapshot(a, b)
    if a.split ~= b.split then return false end
    if a.width ~= b.width then return false end
    if a.height ~= b.height then return false end
    if a.id ~= b.id then return false end
    if (a.a == nil) ~= (b.a == nil) then return false end
    if a.a then
        return same_snapshot(a.a, b.a) and same_snapshot(a.b, b.b)
    end
    return true
end

local function validate_tree(root, seed, step, opdesc)
    local function ctx(msg)
        return ("seed=%d step=%d op=%s: %s"):format(seed, step, opdesc, msg)
    end

    local function rec(node)
        assert_true(type(node.width) == "number" and type(node.height) == "number", ctx("missing dimensions"))
        assert_true(is_int(node.width) and is_int(node.height), ctx("non-integer node size"))
        assert_true(node.width >= 1 and node.height >= 1, ctx("non-positive node size"))

        if not node.split_type then
            assert_true(node.window ~= nil, ctx("leaf missing window"))
            assert_true(node.window.frame == node, ctx("leaf window.frame not synchronized"))
            assert_true(node.width >= node.window:minwidth(), ctx("leaf width below minwidth"))
            assert_true(node.height >= node.window:minheight(), ctx("leaf height below minheight"))
            return
        end

        local a, b = node.children[1], node.children[2]
        assert_true(a ~= nil and b ~= nil, ctx("split missing child"))
        assert_true(a.parent == node and b.parent == node, ctx("child parent pointer mismatch"))

        if node.split_type == "v" then
            assert_true(a.height == node.height and b.height == node.height, ctx("vertical child heights mismatch"))
            assert_true((a.width + b.width) == node.width, ctx("vertical width sum mismatch"))
        elseif node.split_type == "h" then
            assert_true(a.width == node.width and b.width == node.width, ctx("horizontal child widths mismatch"))
            assert_true((a.height + b.height) == node.height, ctx("horizontal height sum mismatch"))
        else
            fail(ctx("unknown split type " .. tostring(node.split_type)))
        end

        rec(a)
        rec(b)
    end

    rec(root)

    -- Full coverage check: every integer cell in root must map to a leaf.
    for y = 1, root.height do
        for x = 1, root.width do
            local leaf = FrameTree.GetFrameAt(root, x, y)
            assert_true(leaf ~= nil and not leaf.split_type, ctx(("uncovered cell %d,%d"):format(x, y)))
        end
    end

    -- Spot-check leaf anchors through GetXY -> GetFrameAt.
    local leaves = collect_leaves(root)
    for i = 1, #leaves do
        local leaf = leaves[i]
        local x, y = FrameTree.GetXY(leaf)
        local hit = FrameTree.GetFrameAt(root, x, y)
        assert_true(hit == leaf, ctx(("GetXY/GetFrameAt mismatch at leaf %d"):format(leaf.window.winnr)))
    end
end

local function run_scenario(seed, equalalways)
    math.randomseed(seed)
    Options.set("equalalways", equalalways)

    local next_winnr = 1
    local function make_win(minw, minh)
        local winnr = next_winnr
        next_winnr = next_winnr + 1
        return {
            winnr = winnr,
            minwidth = function() return minw end,
            minheight = function() return minh end,
        }
    end

    local root = FrameTree.New(make_win(math.random(1, 4), math.random(1, 3)), 80, 24)

    -- Build a nontrivial tree first.
    for i = 1, 18 do
        local leaves = collect_leaves(root)
        local target = leaves[math.random(#leaves)]
        local new_win = make_win(math.random(1, 7), math.random(1, 5))
        local place_second = (math.random(0, 1) == 1)
        local vertical = (math.random(0, 1) == 1)
        local ok, new_root
        if vertical then
            ok, new_root = FrameTree.VerticalSplit(target, new_win, place_second)
        else
            ok, new_root = FrameTree.HorizontalSplit(target, new_win, place_second)
        end
        if ok and new_root and not new_root.parent then
            root = new_root
        end
        validate_tree(root, seed, -i, "bootstrap")
    end

    for step = 1, 2500 do
        local op = math.random(1, 100)
        local opdesc = "unknown"

        if op <= 20 then
            -- Regression target: split a window, then close it immediately.
            local leaves = collect_leaves(root)
            local target = leaves[math.random(#leaves)]
            local before = snapshot_tree(root)
            local new_win = make_win(math.random(1, 7), math.random(1, 5))
            local place_second = (math.random(0, 1) == 1)
            local vertical = (math.random(0, 1) == 1)
            opdesc = vertical and "splitclose_v" or "splitclose_h"

            local ok, new_root
            if vertical then
                ok, new_root = FrameTree.VerticalSplit(target, new_win, place_second)
            else
                ok, new_root = FrameTree.HorizontalSplit(target, new_win, place_second)
            end

            if ok then
                if new_root and not new_root.parent then
                    root = new_root
                end
                assert_true(new_win.frame ~= nil, ("seed=%d step=%d splitclose missing frame"):format(seed, step))
                local close_ok, maybe_root = FrameTree.Close(new_win.frame)
                assert_true(close_ok, ("seed=%d step=%d splitclose close failed"):format(seed, step))
                assert_true(new_win.frame == nil, ("seed=%d step=%d splitclose stale frame pointer"):format(seed, step))
                if maybe_root then
                    root = maybe_root
                end
                local after = snapshot_tree(root)
                assert_true(same_snapshot(before, after),
                    ("seed=%d step=%d splitclose tree mismatch after roundtrip"):format(seed, step))
            else
                assert_true(new_win.frame == nil, ("seed=%d step=%d failed split assigned frame"):format(seed, step))
            end
        elseif op <= 50 then
            -- Root resize
            local dw = math.random(-4, 4)
            local dh = math.random(-3, 3)

            -- Keep root dimensions bounded so coverage checks remain fast.
            if root.width + dw > 140 then dw = 140 - root.width end
            if root.width + dw < 20 then dw = 20 - root.width end
            if root.height + dh > 60 then dh = 60 - root.height end
            if root.height + dh < 8 then dh = 8 - root.height end

            if dw == 0 and dh == 0 then
                dw = (root.width < 140) and 1 or -1
            end

            opdesc = ("root(%d,%d)"):format(dw, dh)
            FrameTree.RootResize(root, dw, dh)
        else
            -- Leaf resize
            local leaves = collect_leaves(root)
            local target = leaves[math.random(#leaves)]
            if math.random(0, 1) == 1 then
                local d = math.random(-4, 4)
                if d == 0 then d = 1 end
                opdesc = ("leafw(%d,%d)"):format(target.window.winnr, d)
                FrameTree.ResizeWidth(target, d)
            else
                local d = math.random(-3, 3)
                if d == 0 then d = 1 end
                opdesc = ("leafh(%d,%d)"):format(target.window.winnr, d)
                FrameTree.ResizeHeight(target, d)
            end
        end

        validate_tree(root, seed, step, opdesc)
    end
end

local scenarios = {
    { seed = 101, equalalways = false },
    { seed = 202, equalalways = false },
    { seed = 303, equalalways = true },
    { seed = 404, equalalways = true },
}

for i = 1, #scenarios do
    local s = scenarios[i]
    run_scenario(s.seed, s.equalalways)
end

print("frametree resize fuzzer runtime tests: OK")
