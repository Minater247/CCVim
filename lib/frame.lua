local FrameTree = {}
local Error = loadModule("lib.error")
local AutoCmd = loadModule("lib.autocmd")

---@class FrameTree

local function trunc_int(n)
    n = tonumber(n) or 0
    if n > 0 then
        return math.floor(n)
    elseif n < 0 then
        return math.ceil(n)
    end
    return 0
end

local function clamp_nonnegative(n)
    if n < 0 then
        return 0
    end
    return n
end

local function split_int_even(delta)
    delta = trunc_int(delta)
    local a = math.floor(delta / 2)
    local b = delta - a
    return a, b
end

local function allocate_even_shrink(need, cap1, cap2)
    need = clamp_nonnegative(trunc_int(need))
    cap1 = clamp_nonnegative(trunc_int(cap1))
    cap2 = clamp_nonnegative(trunc_int(cap2))

    local take1, take2 = 0, 0
    while (take1 + take2) < need do
        local progressed = false
        if take1 < cap1 and (take1 <= take2 or take2 >= cap2) then
            take1 = take1 + 1
            progressed = true
        elseif take2 < cap2 then
            take2 = take2 + 1
            progressed = true
        elseif take1 < cap1 then
            take1 = take1 + 1
            progressed = true
        end

        if not progressed then
            break
        end
    end

    return take1, take2
end

local function new_frame(parent, window, width, height)
    return {
        parent = parent,
        window = window,
        width = width,
        height = height
    }
end

FrameTree.New = function(window, width, height)
    local frm = new_frame(nil, window, width, height)
    window.frame = frm
    return frm
end

local function get_horizontal_resizability(node)
    if node.split_type then
        if node.split_type == "v" then
            -- left-right
            return get_horizontal_resizability(node.children[1]) + get_horizontal_resizability(node.children[2])
        elseif node.split_type == "h" then
            -- top-bottom
            return math.min(
                get_horizontal_resizability(node.children[1]),
                get_horizontal_resizability(node.children[2])
            )
        end
    else
        local can = node.width - node.window:minwidth()
        LOG_INTERNAL(
            "frametree",
            "Horizontal resizability: %d is %d (%d - %d)",
            node.window.winnr,
            can,
            node.width,
            node.window:minwidth()
        )
        return clamp_nonnegative(can)
    end
end

local function get_vertical_resizability(node)
    if node.split_type then
        if node.split_type == "v" then
            -- left-right
            return math.min(get_vertical_resizability(node.children[1]), get_vertical_resizability(node.children[2]))
        elseif node.split_type == "h" then
            -- top-bottom
            return get_vertical_resizability(node.children[1]) + get_vertical_resizability(node.children[2])
        end
    else
        return clamp_nonnegative(node.height - node.window:minheight())
    end
end

local function push_width_resize(node, delta)
    delta = trunc_int(delta)
    if node.split_type then
        if node.split_type == "v" then
            -- left-right
            local amt = push_width_resize(node.children[2], delta)
            delta = delta - amt
            local done = amt

            if delta ~= 0 then
                done = done + push_width_resize(node.children[1], delta)
            end
            node.width = node.width + done
            return done
        elseif node.split_type == "h" then
            -- top-bottom
            if delta < 0 then
                local shrink_cap = clamp_nonnegative(get_horizontal_resizability(node))
                delta = math.max(delta, -shrink_cap)
            end
            push_width_resize(node.children[1], delta)
            push_width_resize(node.children[2], delta)
            node.width = node.width + delta
            return delta
        end
    else
        -- basic case - this is a leaf
        if delta < 0 then
            local max_shrink = clamp_nonnegative(node.width - node.window:minwidth())
            if -delta > max_shrink then
                delta = -max_shrink
            end
        end
        node.width = node.width + delta
        return delta
    end
end

local function push_height_resize(node, delta)
    delta = trunc_int(delta)
    if node.split_type then
        if node.split_type == "v" then
            -- left-right
            if delta < 0 then
                local shrink_cap = clamp_nonnegative(get_vertical_resizability(node))
                delta = math.max(delta, -shrink_cap)
            end
            push_height_resize(node.children[1], delta)
            push_height_resize(node.children[2], delta)
            node.height = node.height + delta
            return delta
        elseif node.split_type == "h" then
            -- top-bottom
            local amt = push_height_resize(node.children[2], delta)
            delta = delta - amt
            local done = amt

            if delta ~= 0 then
                done = done + push_height_resize(node.children[1], delta)
            end
            node.height = node.height + done
            return done
        end
    else
        -- basic case - this is a leaf
        if delta < 0 then
            local max_shrink = clamp_nonnegative(node.height - node.window:minheight())
            if -delta > max_shrink then
                delta = -max_shrink
            end
        end
        node.height = node.height + delta
        return delta
    end
end

local function getOtherChild(node)
    if not node.parent then
        LOG_ERROR("Passed in a node without a parent! Split type: " .. (node.split_type or "nil"))
        return nil
    end

    if node.parent.children[1] == node then
        return node.parent.children[2]
    end

    return node.parent.children[1]
end

-- pushability: the amount we can push other frames out of the way to make this one larger
local function get_horizontal_pushability(node)
    if not node.parent then
        return 0
    end

    -- local retval = get_horizontal_resizability(getOtherChild(node)) + get_horizontal_pushability(node.parent)

    local retval = get_horizontal_pushability(node.parent)
    if node.parent.split_type == "v" then
        retval = retval + get_horizontal_resizability(getOtherChild(node))
    end

    if node.window then
        LOG_INTERNAL("frametree", "Pushability of %d width %d is %d", node.window.winnr, node.width, retval)
    end

    return retval
end

local function get_vertical_pushability(node)
    if not node.parent then
        return 0
    end

    LOG_INTERNAL("frametree", "Fetching parent of " ..
        (node.window and node.window.winnr or "frame") ..
        ", who has parent " .. (node.parent.window and node.parent.window.winnr or "frame"))
    local retval = get_vertical_pushability(node.parent)
    if node.parent.split_type == "h" then
        retval = retval + get_vertical_resizability(getOtherChild(node))
    end

    LOG_INTERNAL(
        "frametree",
        "Pushability of %s height %d is %d",
        tostring(node.window and node.window.winnr or "frame"),
        node.height,
        retval
    )

    return retval
end

-- Evenly apply a *width* delta to a subtree.
-- Negative delta = shrink subtree width, distributing across all shrinkable leaves.
-- Positive delta = (rarely used here) we split evenly for v-splits; for h-splits it broadcasts.
local function apply_width_delta_even(node, delta)
    delta = trunc_int(delta)
    if delta == 0 then return 0 end

    if not node.split_type then
        -- Leaf: clamp by minwidth on shrink
        local want = delta
        if want < 0 then
            local minw = node.window:minwidth()
            local max_shrink = clamp_nonnegative(node.width - minw)
            if -want > max_shrink then want = -max_shrink end
        end
        node.width = node.width + want
        return want
    end

    if node.split_type == "h" then
        -- Stacked (top/bottom): width change must apply equally to both children.
        local want = delta
        if want < 0 then
            local shrink_cap = clamp_nonnegative(get_horizontal_resizability(node))
            want = math.max(want, -shrink_cap)
        end
        if want ~= 0 then
            local a = apply_width_delta_even(node.children[1], want)
            local b = apply_width_delta_even(node.children[2], want)
            -- 'want' is guaranteed feasible so both should match; be defensive:
            local applied = (a == b) and a or math.min(a, b)
            node.width = node.width + applied
            return applied
        end
        return 0
    else -- "v"
        -- Side-by-side: split shrink *evenly* across children (water-filling).
        if delta < 0 then
            local need = -delta
            local cap1 = clamp_nonnegative(get_horizontal_resizability(node.children[1]))
            local cap2 = clamp_nonnegative(get_horizontal_resizability(node.children[2]))
            local take1, take2 = allocate_even_shrink(need, cap1, cap2)
            local a = -take1
            local b = -take2
            local got1 = apply_width_delta_even(node.children[1], a)
            local got2 = apply_width_delta_even(node.children[2], b)
            local applied = got1 + got2 -- both negative, sum negative
            node.width = node.width + applied
            return applied
        else
            -- Growing this subtree (not the stealing side): split evenly by default.
            local a_half, b_half = split_int_even(delta)
            local a = apply_width_delta_even(node.children[1], a_half)
            local b = apply_width_delta_even(node.children[2], b_half)
            local applied = a + b
            node.width = node.width + applied
            return applied
        end
    end
end

-- Evenly apply a *height* delta to a subtree.
-- Negative delta = shrink subtree height, distributing across all shrinkable leaves.
-- Positive delta = (rarely used here) we split evenly for h-splits; for v-splits it broadcasts.
local function apply_height_delta_even(node, delta)
    delta = trunc_int(delta)
    if delta == 0 then return 0 end

    if not node.split_type then
        -- Leaf: clamp by minheight on shrink
        local want = delta
        if want < 0 then
            local minh = node.window:minheight()
            local max_shrink = clamp_nonnegative(node.height - minh)
            if -want > max_shrink then want = -max_shrink end
        end
        node.height = node.height + want
        return want
    end

    if node.split_type == "v" then
        -- Side-by-side: height change must apply equally to both children.
        local want = delta
        if want < 0 then
            local shrink_cap = clamp_nonnegative(get_vertical_resizability(node))
            want = math.max(want, -shrink_cap)
        end
        if want ~= 0 then
            local a = apply_height_delta_even(node.children[1], want)
            local b = apply_height_delta_even(node.children[2], want)
            local applied = (a == b) and a or math.min(a, b)
            node.height = node.height + applied
            return applied
        end
        return 0
    else -- "h"
        -- Stacked (top/bottom): split shrink *evenly* across children (water-filling).
        if delta < 0 then
            local need = -delta
            local cap1 = clamp_nonnegative(get_vertical_resizability(node.children[1]))
            local cap2 = clamp_nonnegative(get_vertical_resizability(node.children[2]))
            local take1, take2 = allocate_even_shrink(need, cap1, cap2)
            local a = -take1
            local b = -take2
            local got1 = apply_height_delta_even(node.children[1], a)
            local got2 = apply_height_delta_even(node.children[2], b)
            local applied = got1 + got2 -- negative
            node.height = node.height + applied
            return applied
        else
            -- Growing this subtree (not the stealing side): split evenly by default.
            local a_half, b_half = split_int_even(delta)
            local a = apply_height_delta_even(node.children[1], a_half)
            local b = apply_height_delta_even(node.children[2], b_half)
            local applied = a + b
            node.height = node.height + applied
            return applied
        end
    end
end


FrameTree.ResizeWidth = function(node, delta)
    delta = trunc_int(delta)
    if delta == 0 then
        return true
    end

    if not node.parent then
        return false
    end

    if delta > 0 then
        local possible = get_horizontal_pushability(node)
        LOG_INTERNAL("frametree", "Resize: Want %d, have %d", delta, possible)
        if possible < delta then
            return false -- TODO: callback for partial resize
        end

        -- Climb toward the root; whenever we encounter a vertical split,
        -- take space from the opposite subtree *evenly* across its leaves.
        while delta > 0 and node.parent do
            if node.parent.split_type == "v" then
                local sibling = getOtherChild(node)
                -- Ask sibling to *shrink* evenly by up to 'delta'
                local did = apply_width_delta_even(sibling, -delta) -- <= 0
                if did > 0 then
                    LOG_ERROR("ResizeWidth: sibling shrink returned positive delta " .. did)
                    return false
                end
                local gained = -did
                if gained > 0 then
                    -- Give the gained width to our target subtree
                    local grew = push_width_resize(node, gained)
                    -- push_width_resize should accept all 'gained'; be defensive:
                    if grew ~= gained then
                        LOG_ERROR("ResizeWidth: grew " .. grew .. " but expected " .. gained)
                        delta = delta - grew
                    else
                        delta = delta - gained
                    end
                end
            else
                LOG_INTERNAL("frametree", "Skipping round (not a vertical split at this level).")
            end
            node = node.parent
            LOG_INTERNAL("frametree", "Moving to " .. (node.window and node.window.winnr or "frame"))
        end
        if delta > 0 then
            return false
        end
    elseif delta < 0 then
        -- Shrinking the target: validate minima along vertical ancestry as before.
        if node.width + delta < node.window:minwidth() then
            return false
        end

        local curr = node
        while curr.parent and curr.parent.split_type == "h" do
            if get_horizontal_resizability(getOtherChild(curr)) < -delta then
                LOG_ERROR("Couldn't resize: id " ..
                    (getOtherChild(curr).window and getOtherChild(curr).window.winnr or "frame") ..
                    " has width " .. getOtherChild(curr).width .. " but we need " .. -delta)
                return false
            end
            curr = curr.parent
        end

        if not curr.parent then
            LOG_ERROR("Bad resize: No vertical splits to give width to")
            return false
        end

        -- Apply as originally (broadcast to the complementary subtrees on 'h' ancestors)
        curr = node
        while curr.parent and curr.parent.split_type == "h" do
            push_width_resize(getOtherChild(curr), delta)
            curr.parent.width = curr.parent.width + delta
            curr = curr.parent
        end
        push_width_resize(getOtherChild(curr), -delta)
        node.width = node.width + delta
    end

    return true
end


FrameTree.ResizeHeight = function(node, delta)
    delta = trunc_int(delta)
    if delta == 0 then
        return true
    end

    if not node.parent then
        return false
    end

    if delta > 0 then
        local possible = get_vertical_pushability(node)
        LOG_INTERNAL("frametree", "Resize: Want %d, have %d", delta, possible)
        if possible < delta then
            return false -- TODO: callback for partial resize
        end

        -- Climb; whenever we encounter a horizontal split,
        -- take space from the opposite subtree *evenly* across its leaves.
        while delta > 0 and node.parent do
            if node.parent.split_type == "h" then
                local sibling = getOtherChild(node)
                -- Ask sibling to *shrink* evenly by up to 'delta'
                local did = apply_height_delta_even(sibling, -delta) -- <= 0
                if did > 0 then
                    LOG_ERROR("ResizeHeight: sibling shrink returned positive delta " .. did)
                    return false
                end
                local gained = -did
                if gained > 0 then
                    -- Give the gained height to our target subtree
                    local grew = push_height_resize(node, gained)
                    if grew ~= gained then
                        LOG_ERROR("ResizeHeight: grew " .. grew .. " but expected " .. gained)
                        delta = delta - grew
                    else
                        delta = delta - gained
                    end
                end
            else
                LOG_INTERNAL("frametree", "Skipping round (not a horizontal split at this level).")
            end
            node = node.parent
            LOG_INTERNAL("frametree", "Moving to " .. (node.window and node.window.winnr or "frame"))
        end
        if delta > 0 then
            return false
        end
    elseif delta < 0 then
        -- Shrinking the target: validate minima along horizontal ancestry as before.
        if node.height + delta < node.window:minheight() then
            return false
        end

        local curr = node
        while curr.parent and curr.parent.split_type == "v" do
            if get_vertical_resizability(getOtherChild(curr)) < -delta then
                LOG_ERROR("Couldn't resize: id " ..
                    (getOtherChild(curr).window and getOtherChild(curr).window.winnr or "frame") ..
                    " has height " .. getOtherChild(curr).height .. " but we need " .. -delta)
                return false
            end
            curr = curr.parent
        end

        if not curr.parent then
            LOG_ERROR("Bad resize: No horizontal splits to give height to")
            return false
        end

        -- Apply as originally (broadcast to the complementary subtrees on 'v' ancestors)
        curr = node
        while curr.parent and curr.parent.split_type == "v" do
            push_height_resize(getOtherChild(curr), delta)
            curr.parent.height = curr.parent.height + delta
            curr = curr.parent
        end
        push_height_resize(getOtherChild(curr), -delta)
        node.height = node.height + delta
    end

    return true
end


local function replace_in_parent(parent, old_child, new_child)
    if not parent or not parent.children then return end
    if parent.children[1] == old_child then
        parent.children[1] = new_child
    elseif parent.children[2] == old_child then
        parent.children[2] = new_child
    end
    new_child.parent = parent
end

local function subtree_min_width(node)
    if not node.split_type then
        return node.window:minwidth()
    end
    if node.split_type == "v" then
        -- side-by-side: widths add
        return subtree_min_width(node.children[1]) + subtree_min_width(node.children[2])
    else -- "h"
        -- stacked: width must accommodate the larger child
        local a = subtree_min_width(node.children[1])
        local b = subtree_min_width(node.children[2])
        return (a > b) and a or b
    end
end

local function subtree_min_height(node)
    if not node.split_type then
        return node.window:minheight()
    end
    if node.split_type == "h" then
        -- stacked: heights add
        return subtree_min_height(node.children[1]) + subtree_min_height(node.children[2])
    else -- "v"
        -- side-by-side: height must accommodate the larger child
        local a = subtree_min_height(node.children[1])
        local b = subtree_min_height(node.children[2])
        return (a > b) and a or b
    end
end


--- Splits a frame into a Left and Right frame.
--- Best-effort equal: prefers 50/50 but accepts asymmetry if mins force it,
--- as long as new_win gets at least its minwidth and the left subtree stays >= its subtree min.
-- place_right: optional boolean. If true, place new_win on the right (old behavior).
FrameTree.VerticalSplit = function(node, new_win, place_right)
    local parent    = node.parent
    local total_w   = node.width
    local new_node  = { parent = parent, width = total_w, height = node.height, split_type = "v" }
    local new_frm = { parent = new_node, window = new_win }

    if node.height < subtree_min_height(node) or node.height < new_win:minheight() then
        return false
    end

    -- Compute feasible target for the existing subtree.
    local half      = math.ceil(total_w / 2)
    local min_existing  = subtree_min_width(node)
    local min_new = new_win:minwidth()
    local max_existing  = total_w - min_new -- leave at least min for new

    if max_existing < min_existing then
        -- Can't allocate the new window's minimum without violating existing subtree minimum.
        return false
    end

    -- Prefer equal, clamp into feasible [min_existing, max_existing].
    local target_existing = half
    if target_existing < min_existing then target_existing = min_existing end
    if target_existing > max_existing then target_existing = max_existing end

    -- Amount we need to shrink the existing subtree (negative if shrink).
    local shrink = target_existing - node.width

    -- Apply shrink: equalalways => even water-fill, else original greedy push.
    if shrink ~= 0 then
        if options.get("equalalways") then
            apply_width_delta_even(node, shrink)
        else
            push_width_resize(node, shrink)
        end
        -- Recompute actual sizes after attempting shrink
        local actual_existing = node.width
        local actual_new = total_w - actual_existing

        if actual_existing < min_existing then
            local need = min_existing - actual_existing
            if need > 0 then
                local grow = push_width_resize(node, need)
                actual_existing = actual_existing + grow
                actual_new = total_w - actual_existing
                if grow < need then
                    return false
                end
            end
        end

        if actual_new < min_new then
            return false
        end
    end

    -- Wire up wrapper
    node.parent = new_node
    new_frm.height = new_node.height
    if place_right then
        new_frm.width = new_node.width - node.width
        new_node.children = { node, new_frm }
        new_win.frame = new_frm
    else
        new_frm.width = total_w - node.width
        new_node.children = { new_frm, node }
        new_frm.parent = new_node
        node.parent = new_node
        new_win.frame = new_frm
    end

    if parent then
        replace_in_parent(parent, node, new_node)
        return true, parent
    else
        return true, new_node
    end
end


--- Splits a frame into a Top and Bottom frame.
--- Best-effort equal: prefers 50/50 but accepts asymmetry if mins force it,
--- as long as new_win gets at least its minheight and the top subtree stays >= its subtree min.
-- place_bottom: optional boolean. If true, place new_win on the bottom (old behavior).
FrameTree.HorizontalSplit = function(node, new_win, place_bottom)
    local parent     = node.parent
    local total_h    = node.height
    local new_node   = { parent = parent, width = node.width, height = total_h, split_type = "h" }
    local new_frm  = { parent = new_node, window = new_win }

    if node.width < subtree_min_width(node) or node.width < new_win:minwidth() then
        return false
    end

    -- Compute feasible target for the existing subtree.
    local half       = math.ceil(total_h / 2)
    local min_existing = subtree_min_height(node)
    local min_new = new_win:minheight()
    local max_existing = total_h - min_new -- leave at least min for new

    if max_existing < min_existing then
        return false
    end

    local target_existing = half
    if target_existing < min_existing then target_existing = min_existing end
    if target_existing > max_existing then target_existing = max_existing end

    local shrink = target_existing - node.height

    -- Apply shrink: equalalways => even water-fill, else original greedy push.
    if shrink ~= 0 then
        if options.get("equalalways") then
            apply_height_delta_even(node, shrink)
        else
            push_height_resize(node, shrink)
        end
        -- Accept partial (best-effort) *of* we still satisfy minima.
        local actual_existing = node.height
        local actual_new = total_h - actual_existing

        if actual_existing < min_existing then
            local need = min_existing - actual_existing
            if need > 0 then
                local grow = push_height_resize(node, need)
                actual_existing = actual_existing + grow
                actual_new = total_h - actual_existing
                if grow < need then
                    return false
                end
            end
        end

        if actual_new < min_new then
            return false
        end
    end

    -- Wire up wrapper
    node.parent = new_node
    new_frm.width = new_node.width
    if place_bottom then
        new_frm.height = new_node.height - node.height
        new_node.children = { node, new_frm }
        new_win.frame = new_frm
    else
        new_frm.height = total_h - node.height
        new_node.children = { new_frm, node }
        new_frm.parent = new_node
        node.parent = new_node
        new_win.frame = new_frm
    end

    if parent then
        replace_in_parent(parent, node, new_node)
        return true, parent
    else
        return true, new_node
    end
end

--- Attempt to equalize sizes throughout a subtree, best effort.
--- Returns true if it made progress (or nothing needed), false if the split
--- is infeasible even for minima (children minima exceed container).
function FrameTree.Equalize(node, axis)
    if not node or not node.split_type then
        return true
    end

    if axis == "vertical" and node.split_type ~= "h" then
        local ok_a = FrameTree.Equalize(node.children[1], axis)
        local ok_b = FrameTree.Equalize(node.children[2], axis)
        return ok_a and ok_b
    elseif axis == "horizontal" and node.split_type ~= "v" then
        local ok_a = FrameTree.Equalize(node.children[1], axis)
        local ok_b = FrameTree.Equalize(node.children[2], axis)
        return ok_a and ok_b
    end

    local function columns(nd)
        -- How many width "lanes" (columns) this subtree contributes
        if not nd or not nd.split_type then
            return 1
        end
        local a, b = nd.children[1], nd.children[2]
        if nd.split_type == "v" then
            return columns(a) + columns(b)
        else -- "h"
            local ca, cb = columns(a), columns(b)
            return (ca > cb) and ca or cb
        end
    end

    local function rows(nd)
        -- How many height "lanes" (rows) this subtree contributes
        if not nd or not nd.split_type then
            return 1
        end
        local a, b = nd.children[1], nd.children[2]
        if nd.split_type == "h" then
            return rows(a) + rows(b)
        else -- "v"
            local ra, rb = rows(a), rows(b)
            return (ra > rb) and ra or rb
        end
    end

    if node.split_type == "v" then
        local a, b = node.children[1], node.children[2]
        local total = node.width

        local minA = subtree_min_width(a)
        local minB = subtree_min_width(b)
        if minA + minB > total then
            FrameTree.Equalize(a, axis); FrameTree.Equalize(b, axis)
            return false
        end

        -- Weight by columnage per nested split
        local uA, uB = columns(a), columns(b)
        local targetA = math.floor((total * uA) / (uA + uB) + 0.5)
        if targetA < minA then targetA = minA end
        if targetA > total - minB then targetA = total - minB end

        local need = targetA - a.width
        if need > 0 then
            local capB = get_horizontal_resizability(b)
            local moved = (need <= capB) and need or capB
            if moved ~= 0 then
                apply_width_delta_even(b, -moved)
                apply_width_delta_even(a, moved)
            end
        elseif need < 0 then
            local capA = get_horizontal_resizability(a)
            local moved = (-need <= capA) and -need or capA
            if moved ~= 0 then
                apply_width_delta_even(a, -moved)
                apply_width_delta_even(b, moved)
            end
        end

        FrameTree.Equalize(a, axis); FrameTree.Equalize(b, axis)
        return true
    elseif node.split_type == "h" then
        local a, b = node.children[1], node.children[2]
        local total = node.height

        local minA = subtree_min_height(a)
        local minB = subtree_min_height(b)
        if minA + minB > total then
            FrameTree.Equalize(a, axis); FrameTree.Equalize(b, axis)
            return false
        end

        local uA, uB = rows(a), rows(b)
        local targetA = math.floor((total * uA) / (uA + uB) + 0.5)
        if targetA < minA then targetA = minA end
        if targetA > total - minB then targetA = total - minB end

        local need = targetA - a.height
        if need > 0 then
            local capB = get_vertical_resizability(b)
            local moved = (need <= capB) and need or capB
            if moved ~= 0 then
                apply_height_delta_even(b, -moved)
                apply_height_delta_even(a, moved)
            end
        elseif need < 0 then
            local capA = get_vertical_resizability(a)
            local moved = (-need <= capA) and -need or capA
            if moved ~= 0 then
                apply_height_delta_even(a, -moved)
                apply_height_delta_even(b, moved)
            end
        end

        FrameTree.Equalize(a, axis)
        FrameTree.Equalize(b, axis)
        return true
    end

    return true
end

FrameTree.GetXY = function(node)
    local curr = node
    local x = 1
    local y = 1
    while curr.parent do
        if curr.parent.children[2] == curr then
            if curr.parent.split_type == "h" then
                y = y + curr.parent.children[1].height
            else
                x = x + curr.parent.children[1].width
            end
        end

        curr = curr.parent
    end

    return x, y
end

FrameTree.DumpTree = function(node)
    -- Print header with a couple of newlines
    LOG_DEBUG("\n\n======")
    LOG_DEBUG("TREE DUMP")
    LOG_DEBUG("======")

    local function dump(n, indent)
        indent = indent or 0
        local prefix = string.rep("  ", indent)

        -- Build a string with the node's basic info.
        local info = prefix

        if n.split_type then
            info = info .. "Frame (split: " .. n.split_type .. ")"
        else
            info = info .. "Leaf Frame"
        end

        if n.window then
            info = info .. " (window id: " .. tostring(n.window.winnr) .. ")"
        end

        info = info .. " [w: " .. tostring(n.width) .. ", h: " .. tostring(n.height) .. "]"
        LOG_DEBUG(info)

        -- If the node has children, recursively dump them
        if n.children then
            for _, child in ipairs(n.children) do
                dump(child, indent + 1)
            end
        end
    end

    dump(node, 0)
end

--- Return the leaf frame that covers (x, y), using 1-based inclusive coordinates.
--- Valid inputs satisfy: 1 <= x <= node.width and 1 <= y <= node.height.
FrameTree.GetFrameAt = function(node, x, y)
    -- Make sure x,y is within the current node's bounds.
    if x < 1 or y < 1 or x > node.width or y > node.height then
        return nil
    end

    -- If the node is split, we must determine which child covers (x,y)
    if node.split_type then
        if node.split_type == "v" then
            -- Vertical split: left and right.
            -- children[1] is the left frame, children[2] the right.
            local left = node.children[1]
            if x <= left.width then
                return FrameTree.GetFrameAt(left, x, y)
            else
                return FrameTree.GetFrameAt(node.children[2], x - left.width, y)
            end
        elseif node.split_type == "h" then
            -- Horizontal split: top and bottom.
            -- children[1] is the top frame, children[2] the bottom.
            local top = node.children[1]
            if y <= top.height then
                return FrameTree.GetFrameAt(top, x, y)
            else
                return FrameTree.GetFrameAt(node.children[2], x, y - top.height)
            end
        else
            -- Unknown split type; just return the node.
            return node
        end
    else
        -- Leaf frame - no further splits, so this is the frame that covers (x,y)
        return node
    end
end

FrameTree.Close = function(node)
    if not node.parent then
        return false
    end

    local parent  = node.parent
    local sibling = getOtherChild(node)

    -- Push the freed extent down into the sibling subtree so that
    -- children's sizes sum to the wrapper's size (no gaps).
    if parent.split_type == "v" then
        -- give sibling the closed node's width
        push_width_resize(sibling, node.width)
    else
        -- give sibling the closed node's height
        push_height_resize(sibling, node.height)
    end

    -- Splice sibling up in place of the parent wrapper.
    if parent.parent then
        local gparent = parent.parent
        if gparent.children[1] == parent then
            gparent.children[1] = sibling
        else
            gparent.children[2] = sibling
        end
        sibling.parent = gparent
        if node.window then
            node.window.frame = nil
        end
        return true
    else
        sibling.parent = nil
        if node.window then
            node.window.frame = nil
        end
        return true, sibling
    end
end

function FrameTree.RootResizeWidth(root, dw)
    dw = trunc_int(dw)
    assert(root and not root.parent, "RootResizeWidth expects the root node")
    if dw == 0 then return true end

    if dw < 0 then
        local can_shrink = get_horizontal_resizability(root)
        if -dw > can_shrink then
            return false
        end
    end

    local done = push_width_resize(root, dw)
    if done ~= dw then
        LOG_ERROR("RootResizeWidth: expected to apply " .. dw .. " but apoplied " .. done)
        return false
    end
    return true
end

function FrameTree.RootResizeHeight(root, dh)
    dh = trunc_int(dh)
    assert(root and not root.parent, "RootResizeHeight expects the root node")
    if dh == 0 then return true end

    if dh < 0 then
        local can_shrink = get_vertical_resizability(root)
        if -dh > can_shrink then
            return false
        end
    end

    local done = push_height_resize(root, dh)
    if done ~= dh then
        LOG_ERROR("RootResizeHeight: expected to apply " .. dh .. "but applied " .. done)
        return false
    end
    return true
end

function FrameTree.RootResize(root, dw, dh)
    dw = trunc_int(dw)
    dh = trunc_int(dh)
    assert(root and not root.parent, "RootResizeDelta expects the root node")
    if (dw == 0) and (dh == 0) then return true end

    if dw < 0 then
        local canW = get_horizontal_resizability(root)
        if -dw > canW then return false end
    end
    if dh < 0 then
        local canH = get_vertical_resizability(root)
        if -dh > canH then return false end
    end

    local doneW = (dw ~= 0) and push_width_resize(root, dw) or 0
    local doneH = (dh ~= 0) and push_height_resize(root, dh) or 0

    if doneW ~= (dw or 0) or doneH ~= (dh or 0) then
        LOG_ERROR("RootResizeDelta: partial apply (w=" .. doneW ..
            "/" .. tostring(dw) .. ", h=" .. doneH .. "/" .. tostring(dh) .. ")")
        return false
    end
    return true
end

local function _window_size_snapshot(win)
    if not win then
        return nil
    end
    if win.frame then
        return { width = win.frame.width, height = win.frame.height }
    end
    if win.floatpos then
        return { width = win.floatpos.w, height = win.floatpos.h }
    end
    return nil
end

local function _snapshot_tab_windows(tabp)
    local out = {}
    if not tabp or not tabp.windows then
        return out
    end

    for i = 1, #tabp.windows do
        local win = tabp.windows[i]
        local snap = _window_size_snapshot(win)
        if snap then
            out[win.winnr] = snap
        end
    end
    return out
end

local function _collect_changed_window_ids(tabp, before)
    local changed = {}
    if not tabp or not tabp.windows then
        return changed
    end

    for i = 1, #tabp.windows do
        local win = tabp.windows[i]
        local now = _window_size_snapshot(win)
        local prev = before and before[win.winnr]
        if now and prev and (now.width ~= prev.width or now.height ~= prev.height) then
            changed[#changed + 1] = win.winnr
        end
    end
    return changed
end

function FrameTree.RebalanceCurrentTab()
    local tabp = tabpages[curtp]
    if not tabp or not tabp.tree then
        return false
    end

    local ok = FrameTree.Equalize(tabp.tree)
    what_redraw["all"] = true
    need_redraw = true
    return ok
end

function FrameTree.ApplyTerminalResize(new_w, new_h, source_event)
    new_w = math.floor(tonumber(new_w) or -1)
    new_h = math.floor(tonumber(new_h) or -1)
    if new_w < 1 or new_h < 1 then
        return false, Error(474, "Invalid terminal size")
    end

    if screen.width == new_w and screen.height == new_h then
        return true, false
    end

    local current_tab = tabpages[curtp]
    local before = _snapshot_tab_windows(current_tab)

    screen.width = new_w
    screen.height = new_h

    options.set("columns", new_w)
    options.set("lines", new_h)

    local strict_failure = false
    for _, tabp in pairs(tabpages) do
        local ok = tabp:updateFrameview()
        if not ok then
            strict_failure = true
        end
    end

    FrameTree.RebalanceCurrentTab()

    local changed_ids = _collect_changed_window_ids(tabpages[curtp], before)

    AutoCmd.Run("VimResized", { force = true })
    if #changed_ids > 0 then
        local first = tostring(changed_ids[1])
        AutoCmd.Run("WinResized", {
            force = true,
            pattern = first,
            bufname = first,
            data = { windows = changed_ids },
        })
    end

    what_redraw["all"] = true
    need_redraw = true

    if strict_failure then
        LOG_DEBUG("terminal resize strict failure event=%s size=%dx%d", tostring(source_event), new_w, new_h)
        return false, Error(36)
    end

    return true, true
end

function FrameTree.IsLeftChild(node)
    if not node.parent then return false end

    while node.parent and node.parent.split_type == "h" do
        node = node.parent
    end

    if not node or not node.parent then return false end

    return (node.parent.split_type == "v") and (node.parent.children[1] == node)
end

function FrameTree.IsTopChild(node)
    if not node.parent then return false end

    while node.parent and node.parent.split_type == "v" do
        node = node.parent
    end

    if not node or not node.parent then return false end

    return (node.parent.split_type == "h") and (node.parent.children[1] == node)
end

--- Return the leaf frame that covers (x,y) and the coordinates local to that frame.
--- @param node table  -- root (or any subtree) to search within
--- @param x integer   -- x coordinate (zero-based by default)
--- @param y integer   -- y coordinate (zero-based by default)
--- @return table|nil frame, integer|nil local_x, integer|nil local_y
function FrameTree.FrameAtWithLocal(node, x, y)
    -- Drop to 0-based for easier traversal
    x = x - 1
    y = y - 1

    local function descend(n, lx, ly)
        -- Out of bounds for this subtree
        if lx < 0 or ly < 0 or lx >= n.width or ly >= n.height then
            return nil, nil, nil
        end

        -- Leaf: we're at the frame that contains the point
        if not n.split_type then
            return n, lx + 1, ly + 1
        end

        if n.split_type == "v" then
            -- Left | Right
            local left = n.children[1]
            if lx < left.width then
                return descend(left, lx, ly)
            else
                return descend(n.children[2], lx - left.width, ly)
            end
        elseif n.split_type == "h" then
            -- Top
            local top = n.children[1]
            if ly < top.height then
                return descend(top, lx, ly)
            else
                -- Bottom
                return descend(n.children[2], lx, ly - top.height)
            end
        else
            -- Unknown split: treat as leaf
            return n, lx + 1, ly + 1
        end
    end

    return descend(node, x, y)
end

FrameTree.self_tests = function()
    local create_window = function()
        local window = FrameTree.New(
            { winnr = 0, minwidth = function() return 1 end, minheight = function() return 1 end }, 80, 25)

        -- window should be fine
        assert(window.width == 80, "'create_window': Invalid window width " .. window.width)
        assert(window.height == 25, "'create_window': Invalid window height " .. window.height)

        -- zero size resize should succeed
        assert(FrameTree.ResizeWidth(window, 0), "'create_window': Resize of size 0 should work (width)")
        assert(FrameTree.ResizeHeight(window, 0), "'create_window': Resize of size 0 should work (height)")

        -- nonzero size resize should not succeed
        assert(
            not FrameTree.ResizeWidth(window, 1),
            "'create_window': Resize of size non-0 should not work (+width)"
        )
        assert(
            not FrameTree.ResizeHeight(window, 1),
            "'create_window': Resize of size non-0 should not work (+height)"
        )
        assert(
            not FrameTree.ResizeWidth(window, -1),
            "'create_window': Resize of size non-0 should not work (-width)"
        )
        assert(
            not FrameTree.ResizeHeight(window, -1),
            "'create_window': Resize of size non-0 should not work (-height)"
        )
    end

    local split_window_vert = function()
        local me = "'split_window_vert': "

        local root = FrameTree.New(
            { winnr = 0, minwidth = function() return 1 end, minheight = function() return 1 end },
            80, 25)

        -- split should succeed
        local success, new_root = FrameTree.VerticalSplit(root,
            { winnr = 1, minwidth = function() return 1 end, minheight = function() return 1 end }, true)
        assert(success and new_root, me .. "Split should succeed")
        root = new_root

        -- width of root window should be the same
        assert(root.width == 80, me .. "Invalid root width " .. root.width)
        assert(root.height == 25, me .. "Invalid root height " .. root.height)

        assert(root.children, me .. "Root should have children")
        assert(#root.children == 2, me .. "Root should have 2 children")

        assert(root.children[1].window.winnr == 0,
            me .. "Left child should be old root node, but is ID " .. root.children[1].window.winnr)
        assert(root.children[2].window.winnr == 1,
            me .. "Right child should be new window, but is ID " .. root.children[2].window.winnr)

        assert(root.children[1].width == 40, me .. "Left child should have width 40, has " .. root.children[1].width)
        assert(root.children[2].width == 40, me .. "Right child should have width 40, has " .. root.children[2].width)

        assert(root.children[1].height == 25, me .. "Left child height should be 25, have " .. root.children[1].height)
        assert(root.children[2].height == 25, me .. "Right child height should be 25, have " .. root.children[2].height)

        assert(root.children[1].parent == root, me .. "Left child should be parented to the root node")
        assert(root.children[2].parent == root, me .. "Right child should be parented to the root node")
    end

    local split_window_horiz = function()
        local me = "'split_window_horiz': "

        local root = FrameTree.New(
            { winnr = 0, minwidth = function() return 1 end, minheight = function() return 1 end },
            80, 25)

        -- split should succeed
        local success, new_root = FrameTree.HorizontalSplit(root,
            { winnr = 1, minwidth = function() return 1 end, minheight = function() return 1 end }, true)
        assert(success and new_root, me .. "Split should succeed")
        root = new_root

        -- width of root window should be the same
        assert(root.width == 80, me .. "Invalid root width " .. root.width)
        assert(root.height == 25, me .. "Invalid root height " .. root.height)

        assert(root.children, me .. "Root should have children")
        assert(#root.children == 2, me .. "Root should have 2 children")

        assert(root.children[1].window.winnr == 0,
            me .. "Top child should be old root node, but is ID " .. root.children[1].window.winnr)
        assert(root.children[2].window.winnr == 1,
            me .. "Bottom child should be new window, but is ID " .. root.children[2].window.winnr)

        assert(root.children[1].width == 80, me .. "Top child should have width 40, has " .. root.children[1].width)
        assert(root.children[2].width == 80, me .. "Bottom child should have width 40, has " .. root.children[2].width)

        assert(root.children[1].height == 13, me .. "Top child height should be 25, have " .. root.children[1].height)
        assert(
            root.children[2].height == 12,
            me .. "Bottom child height should be 25, have " .. root.children[2].height
        )

        assert(root.children[1].parent == root, me .. "Top child should be parented to the root node")
        assert(root.children[2].parent == root, me .. "Bottom child should be parented to the root node")
    end

    local split_window_twice = function()
        local me = "'split_window_twice': "

        local root = FrameTree.New(
            { winnr = 0, minwidth = function() return 1 end, minheight = function() return 1 end },
            80, 25)

        local success, new_root = FrameTree.VerticalSplit(root,
            { winnr = 1, minwidth = function() return 1 end, minheight = function() return 1 end }, true)
        assert(success and new_root, me .. "Split should succeed")
        root = new_root

        success = FrameTree.VerticalSplit(root.children[2],
            { winnr = 2, minwidth = function() return 1 end, minheight = function() return 1 end }, true)
        assert(success, me .. "Second split should succeed")

        assert(root.children, me .. "Root should have children")
        assert(#root.children == 2, me .. "Root should have 2 children")

        -- width of root window should be the same
        assert(root.width == 80, me .. "Invalid root width " .. root.width)
        assert(root.height == 25, me .. "Invalid root height " .. root.height)

        assert(root.children[1].window.winnr == 0,
            me .. "Left child should be old root node, but is ID " .. root.children[1].window.winnr)
        assert(not root.children[2].window,
            me ..
            "Left child should not have a window, but has window with ID " ..
            (root.children[2].window and root.children[2].window.winnr or "unknown"))

        assert(root.children[2].children, me .. "Right child of root should have children")
        assert(root.children[2].children[1].window.winnr == 1,
            me ..
            "Left child of right side should have window ID 1, but has " .. root.children[2].children[1].window.winnr)
        assert(root.children[2].children[2].window.winnr == 2,
            me ..
            "Right child of right side should have window ID 2, but has " .. root.children[2].children[2].window.winnr)

        assert(root.children[2].children[1].parent == root.children[2],
            me .. "Left child of right side should have parent the right of root")
        assert(root.children[2].children[2].parent == root.children[2],
            me .. "Right child of right side should have parent of the right of root")
        assert(root.children[2].parent == root, me .. "Right side frame should be parented to root")

        assert(
            root.children[1].width == 40,
            me .. "Left child should have width 40, but has " .. root.children[1].width
        )
        assert(root.children[2].children[1].width == 20,
            "Left child of right side should have width 20, but has " .. root.children[2].children[1].width)
        assert(root.children[2].children[2].width == 20,
            "Right child of left side should have width 20, but has " .. root.children[2].children[2].width)

        assert(root.children[1].height == 25,
            me .. "Left child should have height 25, but has " .. root.children[1].height)
        assert(root.children[2].children[1].height == 25,
            me .. "Left child of right side should have height 25, but has " .. root.children[2].children[1].height)
        assert(root.children[2].children[2].height == 25,
            me .. "Right child of left side should have height 25, but has " .. root.children[2].children[2].height)
    end

    local resize_split_window = function()
        local me = "'resize_split_window'"

        local root = FrameTree.New(
            { winnr = 0, minwidth = function() return 1 end, minheight = function() return 1 end },
            80, 25)

        local success, new_root = FrameTree.VerticalSplit(root,
            { winnr = 1, minwidth = function() return 1 end, minheight = function() return 1 end }, true)
        assert(success and new_root, me .. "Split should succeed")
        root = new_root

        FrameTree.ResizeWidth(root.children[2], 10)

        assert(root.children, me .. "Root should have children")
        assert(#root.children == 2, me .. "Root should have 2 children")

        -- width of root window should be the same
        assert(root.width == 80, me .. "Invalid root width " .. root.width)
        assert(root.height == 25, me .. "Invalid root height " .. root.height)

        assert(root.children[1].window.winnr == 0,
            "Left child should be old root node, but is ID " .. root.children[1].window.winnr)
        assert(root.children[2].window.winnr == 1,
            "Right child should be window with ID 1, but is ID " .. root.children[2].window.winnr)

        assert(
            root.children[1].width == 30,
            me .. "Left child should have width 30, but has " .. root.children[1].width
        )
        assert(
            root.children[2].width == 50,
            me .. "Right child should have width 50, but has " .. root.children[2].width
        )

        assert(root.children[1].height == 25,
            me .. "Left child should have height 25, but has " .. root.children[1].height)
        assert(root.children[2].height == 25,
            me .. "Right child should have height 25, but has " .. root.children[2].height)
    end

    local resize_multi_split_window_horiz = function()
        local me = "'resize_multi_split_window_horiz'"

        local root = FrameTree.New(
            { winnr = 0, minwidth = function() return 1 end, minheight = function() return 1 end },
            80, 25)

        local success, new_root = FrameTree.VerticalSplit(root,
            { winnr = 1, minwidth = function() return 1 end, minheight = function() return 1 end }, true)
        assert(success and new_root, me .. "Split should succeed")
        root = new_root

        success = FrameTree.HorizontalSplit(root.children[2]
            { winnr = 2, minwidth = function() return 1 end, minheight = function() return 1 end }, true)
        assert(success, me .. "Split should succeed")

        FrameTree.DumpTree(root)

        FrameTree.ResizeWidth(root.children[2].children[2], 10)

        FrameTree.DumpTree(root)
    end

    local tests = {
        create_window,
        split_window_vert,
        split_window_horiz,
        split_window_twice,
        resize_split_window,
        resize_multi_split_window_horiz,
    }

    LOG_DEBUG("frame.lua: Running " .. #tests .. " self tests.")
    local fails = 0
    for i = 1, #tests do
        LOG_DEBUG("frame.lua: Running self test " .. i)
        xpcall(tests[i], function(err)
            -- Print traceback
            local traceback = debug.traceback(err)
            -- Get error details like function and line number
            LOG_ERROR(traceback)
            fails = fails + 1
        end)
    end
    if fails == 0 then
        LOG_DEBUG("frame.lua: All self tests passed!")
    else
        LOG_DEBUG("frame.lua: Self tests: " .. #tests - fails .. "/" .. #tests .. " passed.")
    end

    return (fails == 0)
end


return FrameTree
