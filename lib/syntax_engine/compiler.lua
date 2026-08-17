local Compiler = {}

local function copy_array(src)
    if not src then return nil end
    local out = {}
    for i = 1, #src do out[i] = src[i] end
    return out
end

local function copy_kv(src)
    if not src then return nil end
    local out = {}
    for k, v in pairs(src) do out[k] = v end
    return out
end

local function copy_options(opts)
    if not opts then return nil end
    return {
        flags = copy_kv(opts.flags) or {},
        attrs = copy_kv(opts.attrs) or {},
        contains = copy_array(opts.contains),
        containedin = copy_array(opts.containedin),
        nextgroup = copy_array(opts.nextgroup),
        add = copy_array(opts.add),
        remove = copy_array(opts.remove),
        cchar = opts.cchar,
        matchgroup = opts.matchgroup,
        unknown = copy_array(opts.unknown) or {},
    }
end

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function looks_like_pattern(name)
    return name:find("[%*%[%]%.%^%$%+%?]") ~= nil
end

local function sorted_ids_from_set(set)
    local ids = {}
    for id in pairs(set) do ids[#ids + 1] = id end
    table.sort(ids)
    return ids
end

local function set_to_array(set)
    local out = {}
    for id in pairs(set) do out[#out + 1] = id end
    table.sort(out)
    return out
end

local function ids_to_bitset(ids)
    local words = {}
    for i = 1, #ids do
        local id = ids[i]
        local word = math.floor((id - 1) / 32) + 1
        local bit = (id - 1) % 32
        if bit32 then
            words[word] = bit32.bor(words[word] or 0, bit32.lshift(1, bit))
        else
            words[word] = (words[word] or 0) + (2 ^ bit)
        end
    end
    return words
end

local function merge_set(dst, src)
    for k in pairs(src) do dst[k] = true end
end

local function clear_set(dst, src)
    for k in pairs(src) do dst[k] = nil end
end

local function ensure_group(state, name)
    name = trim(name or "")
    if name == "" then return nil end

    local id = state.group_ids[name]
    if id then return id end

    id = state.next_group_id
    state.next_group_id = id + 1
    state.group_ids[name] = id
    state.groups[id] = {
        id = id,
        name = name,
        item_ids = {},
        keyword_item_ids = {},
        has_contained = false,
        has_top = false,
    }
    return id
end

local function ensure_cluster(state, name)
    name = trim(name or "")
    if name == "" then return nil end

    local id = state.cluster_ids[name]
    if id then return id end

    id = state.next_cluster_id
    state.next_cluster_id = id + 1
    state.cluster_ids[name] = id
    state.clusters[id] = {
        id = id,
        name = name,
        ops = {},
    }
    return id
end

local function new_state()
    return {
        case_mode = "match",
        syntax_iskeyword = nil,
        group_ids = {},
        groups = {},
        next_group_id = 1,
        cluster_ids = {},
        clusters = {},
        next_cluster_id = 1,
        items = {},
        includes = {},
        sync = {
            fromstart = false,
            ccomment = false,
            ccomment_group = nil,
            minlines = nil,
            maxlines = nil,
            linebreaks = nil,
            linecont = nil,
            items = {},
        },
    }
end

local function add_item(state, kind, group_name, options, payload)
    local group_id = ensure_group(state, group_name)
    if options and options.matchgroup then
        ensure_group(state, options.matchgroup)
    end
    if payload then
        for _, specs in pairs(payload) do
            if type(specs) == "table" then
                for i = 1, #specs do
                    local spec = specs[i]
                    if type(spec) == "table" and spec.matchgroup then
                        ensure_group(state, spec.matchgroup)
                    end
                end
            end
        end
    end
    local id = #state.items + 1
    local item = {
        id = id,
        kind = kind,
        group = group_name,
        group_id = group_id,
        ignore_case = (state.case_mode == "ignore"),
        options = copy_options(options) or { flags = {}, attrs = {}, unknown = {} },
        payload = payload,
    }
    state.items[id] = item
end

local function add_sync_item(state, parsed_item)
    local id = #state.sync.items + 1
    state.sync.items[id] = {
        id = id,
        kind = parsed_item.kind,
        sync_group = parsed_item.sync_group,
        sync_point = parsed_item.sync_point,
        target_group = parsed_item.target_group,
        pattern = parsed_item.pattern,
        patterns = parsed_item.patterns and {
            start = copy_array(parsed_item.patterns.start) or {},
            skip = copy_array(parsed_item.patterns.skip) or {},
            ["end"] = copy_array(parsed_item.patterns["end"]) or {},
        },
        options = copy_options(parsed_item.options) or { flags = {}, attrs = {}, unknown = {} },
    }
end

local function filter_items_remove_groups(state, remove_group_ids)
    if not next(remove_group_ids) then return end

    local kept = {}
    for i = 1, #state.items do
        local item = state.items[i]
        if not remove_group_ids[item.group_id] then
            kept[#kept + 1] = item
        end
    end

    state.items = kept
    for i = 1, #state.items do
        state.items[i].id = i
    end
end

local function apply_clear(state, cmd)
    if cmd.scope == "all" then
        state.items = {}
        state.sync.items = {}
        for _, cluster in pairs(state.clusters) do
            cluster.ops = { { op = "set", specs = {} } }
        end
        return
    end

    local remove_group_ids = {}
    for i = 1, #cmd.groups do
        local gid = ensure_group(state, cmd.groups[i])
        if gid then remove_group_ids[gid] = true end
    end
    filter_items_remove_groups(state, remove_group_ids)

    for i = 1, #cmd.clusters do
        local cid = ensure_cluster(state, cmd.clusters[i])
        if cid then
            state.clusters[cid].ops[#state.clusters[cid].ops + 1] = { op = "set", specs = {} }
        end
    end
end

local function apply_cluster(state, cmd)
    local cid = ensure_cluster(state, cmd.name)
    if not cid then return end
    local cluster = state.clusters[cid]

    if cmd.contains then
        cluster.ops[#cluster.ops + 1] = { op = "set", specs = copy_array(cmd.contains) }
    end
    if cmd.add then
        cluster.ops[#cluster.ops + 1] = { op = "add", specs = copy_array(cmd.add) }
    end
    if cmd.remove then
        cluster.ops[#cluster.ops + 1] = { op = "remove", specs = copy_array(cmd.remove) }
    end
end

local function apply_include(state, cmd)
    local include = {
        cluster = nil,
        cluster_id = nil,
        file = cmd.file or "",
    }

    if cmd.cluster and cmd.cluster ~= "" then
        include.cluster = cmd.cluster
        include.cluster_id = ensure_cluster(state, cmd.cluster)
    end

    state.includes[#state.includes + 1] = include
end

local function apply_sync(state, cmd)
    if cmd.action == "clear" then
        if #cmd.clear_names == 0 then
            state.sync.items = {}
        else
            local remove = {}
            for i = 1, #cmd.clear_names do
                remove[cmd.clear_names[i]] = true
            end
            local kept = {}
            for i = 1, #state.sync.items do
                local item = state.sync.items[i]
                if not remove[item.sync_group or ""] then
                    kept[#kept + 1] = item
                end
            end
            state.sync.items = kept
            for i = 1, #state.sync.items do
                state.sync.items[i].id = i
            end
        end
    end

    if cmd.settings.fromstart ~= nil then state.sync.fromstart = cmd.settings.fromstart end
    if cmd.settings.ccomment ~= nil then state.sync.ccomment = cmd.settings.ccomment end
    if cmd.settings.ccomment_group ~= nil then state.sync.ccomment_group = cmd.settings.ccomment_group end
    if cmd.settings.minlines ~= nil then state.sync.minlines = cmd.settings.minlines end
    if cmd.settings.maxlines ~= nil then state.sync.maxlines = cmd.settings.maxlines end
    if cmd.settings.linebreaks ~= nil then state.sync.linebreaks = cmd.settings.linebreaks end
    if cmd.settings.linecont ~= nil then state.sync.linecont = cmd.settings.linecont end

    for i = 1, #cmd.items do
        add_sync_item(state, cmd.items[i])
    end
end

local function apply_command(state, cmd)
    local kind = cmd.kind
    if kind == "case" then
        if cmd.mode == "match" or cmd.mode == "ignore" then
            state.case_mode = cmd.mode
        end
        return
    end
    if kind == "iskeyword" then
        if cmd.clear then
            state.syntax_iskeyword = nil
        elseif cmd.value then
            state.syntax_iskeyword = cmd.value
        end
        return
    end
    if kind == "keyword" then
        for i = 1, #cmd.keywords do
            add_item(state, "keyword", cmd.group, cmd.options, { keyword = cmd.keywords[i] })
        end
        return
    end
    if kind == "match" then
        add_item(state, "match", cmd.group, cmd.options, { pattern = cmd.pattern })
        return
    end
    if kind == "region" then
        add_item(state, "region", cmd.group, cmd.options, {
            start = copy_array(cmd.patterns.start) or {},
            skip = copy_array(cmd.patterns.skip) or {},
            ["end"] = copy_array(cmd.patterns["end"]) or {},
        })
        return
    end
    if kind == "cluster" then
        apply_cluster(state, cmd)
        return
    end
    if kind == "include" then
        apply_include(state, cmd)
        return
    end
    if kind == "sync" then
        apply_sync(state, cmd)
        return
    end
    if kind == "clear" then
        apply_clear(state, cmd)
        return
    end
end

local function rebuild_group_metadata(state)
    for _, g in pairs(state.groups) do
        g.item_ids = {}
        g.keyword_item_ids = {}
        g.has_contained = false
        g.has_top = false
    end

    for i = 1, #state.items do
        local item = state.items[i]
        local group = state.groups[item.group_id]
        if group then
            group.item_ids[#group.item_ids + 1] = item.id
            if item.kind == "keyword" then
                group.keyword_item_ids[#group.keyword_item_ids + 1] = item.id
            end
            if item.options.flags.contained then
                group.has_contained = true
            else
                group.has_top = true
            end
        end
    end
end

local function all_group_ids_set(state)
    local set = {}
    for id in pairs(state.groups) do set[id] = true end
    return set
end

local function top_group_ids_set(state)
    local set = {}
    for id, group in pairs(state.groups) do
        if group.has_top then set[id] = true end
    end
    return set
end

local function contained_group_ids_set(state)
    local set = {}
    for id, group in pairs(state.groups) do
        if group.has_contained then set[id] = true end
    end
    return set
end

local function resolve_pattern_groups(state, patt)
    local set = {}
    local ok = pcall(string.match, "", patt)
    if not ok then return set end
    for id, group in pairs(state.groups) do
        local matched = pcall(string.match, group.name, patt)
        if matched then
            if group.name:match(patt) then
                set[id] = true
            end
        end
    end
    return set
end

local function resolve_contains_specs(state, specs, resolve_cluster)
    local out = {}
    if not specs or #specs == 0 then
        return out
    end

    local first = specs[1] and specs[1]:upper() or ""
    local idx = 1
    local exclusion_mode = false
    if first == "ALL" then
        out = all_group_ids_set(state)
        idx = 2
    elseif first == "ALLBUT" then
        out = all_group_ids_set(state)
        idx = 2
        exclusion_mode = true
    elseif first == "TOP" then
        out = top_group_ids_set(state)
        idx = 2
    elseif first == "CONTAINED" then
        out = contained_group_ids_set(state)
        idx = 2
    end

    local resolved = {}
    for i = idx, #specs do
        local name = specs[i]
        if name ~= "" then
            if name:sub(1, 1) == "@" then
                local cname = name:sub(2)
                ensure_cluster(state, cname)
                merge_set(resolved, resolve_cluster(cname))
            elseif looks_like_pattern(name) then
                merge_set(resolved, resolve_pattern_groups(state, name))
            else
                local gid = ensure_group(state, name)
                if gid then resolved[gid] = true end
            end
        end
    end

    if exclusion_mode then
        clear_set(out, resolved)
        return out
    end

    merge_set(out, resolved)
    return out
end

local function resolve_clusters(state)
    local cache = {}
    local resolving = {}

    local function resolve_cluster(name)
        if cache[name] then return cache[name] end
        if resolving[name] then return {} end
        resolving[name] = true

        local cid = ensure_cluster(state, name)
        local cluster = cid and state.clusters[cid]
        local members = {}

        if cluster then
            for i = 1, #cluster.ops do
                local op = cluster.ops[i]
                local ids = resolve_contains_specs(state, op.specs, resolve_cluster)
                if op.op == "set" then
                    members = ids
                elseif op.op == "add" then
                    merge_set(members, ids)
                elseif op.op == "remove" then
                    clear_set(members, ids)
                end
            end
        end

        resolving[name] = nil
        cache[name] = members
        return members
    end

    for _, cluster in pairs(state.clusters) do
        resolve_cluster(cluster.name)
    end

    return cache, resolve_cluster
end

local function decorate_options_with_resolved_ids(state, options, resolve_cluster)
    local out = copy_options(options) or { flags = {}, attrs = {}, unknown = {} }

    if out.contains then
        local contains_set = resolve_contains_specs(state, out.contains, resolve_cluster)
        out.contains_ids = sorted_ids_from_set(contains_set)
        out.contains_bits = ids_to_bitset(out.contains_ids)
    end

    if out.containedin then
        local containedin_set = resolve_contains_specs(state, out.containedin, resolve_cluster)
        out.containedin_ids = sorted_ids_from_set(containedin_set)
        out.containedin_bits = ids_to_bitset(out.containedin_ids)
    end

    if out.nextgroup then
        local nextgroup_set = resolve_contains_specs(state, out.nextgroup, resolve_cluster)
        out.nextgroup_ids = sorted_ids_from_set(nextgroup_set)
        out.nextgroup_bits = ids_to_bitset(out.nextgroup_ids)
    end

    return out
end

local function build_keyword_lookup(items)
    local lookup = {
        case_sensitive = {},
        case_sensitive_by_first = {},
        case_insensitive = {},
        case_insensitive_by_first = {},
    }

    local function add(map, key, id)
        local bucket = map[key]
        if not bucket then
            bucket = {}
            map[key] = bucket
        end
        bucket[#bucket + 1] = id
    end

    for i = 1, #items do
        local item = items[i]
        if item.kind == "keyword" and item.payload and item.payload.keyword then
            local word = item.payload.keyword
            if item.ignore_case then
                local key = word:lower()
                add(lookup.case_insensitive, key, item.id)
                add(lookup.case_insensitive_by_first, key:sub(1, 1), item.id)
            else
                add(lookup.case_sensitive, word, item.id)
                add(lookup.case_sensitive_by_first, word:sub(1, 1), item.id)
            end
        end
    end

    return lookup
end

local function deep_freeze(tbl, seen)
    if type(tbl) ~= "table" then return tbl end
    seen = seen or {}
    if seen[tbl] then return tbl end
    seen[tbl] = true

    for _, v in pairs(tbl) do
        if type(v) == "table" then
            deep_freeze(v, seen)
        end
    end

    return setmetatable(tbl, {
        __newindex = function()
            error("attempt to modify immutable syntax IR", 2)
        end,
        __metatable = false,
    })
end

function Compiler.compile(parsed_commands)
    local commands
    if parsed_commands == nil then
        commands = {}
    elseif parsed_commands.kind then
        commands = { parsed_commands }
    else
        commands = parsed_commands
    end

    local state = new_state()
    for i = 1, #commands do
        apply_command(state, commands[i])
    end

    rebuild_group_metadata(state)

    local cluster_members_cache, resolve_cluster = resolve_clusters(state)
    local keyword_lookup = build_keyword_lookup(state.items)

    local groups = {}
    local group_id_map = {}
    for id, group in pairs(state.groups) do
        groups[id] = {
            id = id,
            name = group.name,
            item_ids = copy_array(group.item_ids) or {},
            keyword_item_ids = copy_array(group.keyword_item_ids) or {},
            has_contained = group.has_contained,
            has_top = group.has_top,
        }
        group_id_map[group.name] = id
    end

    local clusters = {}
    local cluster_id_map = {}
    for id, cluster in pairs(state.clusters) do
        local members_set = cluster_members_cache[cluster.name] or {}
        local member_ids = set_to_array(members_set)
        clusters[id] = {
            id = id,
            name = cluster.name,
            ops = copy_array(cluster.ops) or {},
            member_ids = member_ids,
            member_bits = ids_to_bitset(member_ids),
        }
        cluster_id_map[cluster.name] = id
    end

    local items = {}
    local item_order = {}
    for i = 1, #state.items do
        local item = state.items[i]
        items[item.id] = {
            id = item.id,
            kind = item.kind,
            group = item.group,
            group_id = item.group_id,
            ignore_case = item.ignore_case,
            options = decorate_options_with_resolved_ids(state, item.options, resolve_cluster),
            payload = item.payload,
        }
        item_order[#item_order + 1] = item.id
    end

    local sync_items = {}
    for i = 1, #state.sync.items do
        local item = state.sync.items[i]
        sync_items[i] = {
            id = i,
            kind = item.kind,
            sync_group = item.sync_group,
            sync_point = item.sync_point,
            target_group = item.target_group,
            target_group_id = item.target_group and group_id_map[item.target_group],
            pattern = item.pattern,
            patterns = item.patterns,
            options = decorate_options_with_resolved_ids(state, item.options, resolve_cluster),
        }
    end

    local ir = {
        kind = "stage2_ir",
        case_mode = state.case_mode,
        syntax_iskeyword = state.syntax_iskeyword,
        group_ids = group_id_map,
        groups = groups,
        cluster_ids = cluster_id_map,
        clusters = clusters,
        item_order = item_order,
        items = items,
        keyword_lookup = keyword_lookup,
        includes = copy_array(state.includes) or {},
        sync = {
            fromstart = state.sync.fromstart,
            ccomment = state.sync.ccomment,
            ccomment_group = state.sync.ccomment_group,
            minlines = state.sync.minlines,
            maxlines = state.sync.maxlines,
            linebreaks = state.sync.linebreaks,
            linecont = state.sync.linecont,
            items = sync_items,
        },
    }

    return deep_freeze(ir)
end

return Compiler
