-- vim.lib.wordnav
-- Standalone word/WORD navigation (no cursor movement).
-- Booleans for speed:
--   isWORD: false => 'word' (uses 'iskeyword' from *this buffer*), true => 'WORD' (non-blank runs)
--   to_end: false => land on start; true => land on end
-- Public API:
--   WordNav.posNext(win, isWORD, to_end, count, y, x) -> line, col1 | nil
--   WordNav.posPrev(win, isWORD, to_end, count, y, x) -> line, col1 | nil
--   WordNav.posForWordMotion(win, motion, count, y, x) -> line, col1 | nil
--   WordNav.invalidateCache(buf) -- clear this buffer's iskeyword cache

local WordNav = {}

local function _build_iskeyword_set(buf)
	buf._ikw_cache = buf._ikw_cache or { spec = nil, set = nil }
	local spec = options.get("iskeyword", nil, buf)
	if buf._ikw_cache.spec == spec and buf._ikw_cache.set then
		return buf._ikw_cache.set
	end

	local items = options.ParseCSL(spec)
	local set = {}

	local function add_range(b0, b1, rm)
		if b0 > b1 then b0, b1 = b1, b0 end
		for b = b0, b1 do set[b] = rm and nil or true end
	end
	local function apply(tok)
		local rm = false
		if tok:sub(1, 1) == "^" then
			rm = true; tok = tok:sub(2)
		end
		if tok == "@" then
			add_range(string.byte("A"), string.byte("Z"), rm)
			add_range(string.byte("a"), string.byte("z"), rm)
			return
		end
		local n0, n1 = tok:match("^(%d+)%-(%d+)$")
		if n0 then
			add_range(tonumber(n0), tonumber(n1), rm); return
		end
		local c0, c1 = tok:match("^(.)%-(.)$")
		if c0 then
			add_range(string.byte(c0), string.byte(c1), rm); return
		end
		local b = string.byte(tok:sub(1, 1))
		set[b] = rm and nil or true
	end

	for i = 1, #items do apply(items[i]) end
	buf._ikw_cache.spec, buf._ikw_cache.set = spec, set
	return set
end

function WordNav.invalidateCache(buf)
	buf._ikw_cache.spec, buf._ikw_cache.set = nil, nil
end

-- ---------- low-level helpers ----------
local function _line_len(buf, lines, y) return buf:str_len(lines[y] or "") end

local function _fwd(buf, lines, y, x)
	local n = _line_len(buf, lines, y)
	if x < n then return y, x + 1 end
	y = y + 1
	if y > #lines then return nil, nil end
	return y, 1
end

local function _back(buf, lines, y, x)
	if x > 1 then return y, x - 1 end
	y = y - 1
	if y < 1 then return nil, nil end
	local n = _line_len(buf, lines, y)
	if n == 0 then return y, 0 end
	return y, n
end

local function _is_blank(buf, lines, y, x)
	if y < 1 or y > #lines then return true end
	local s = lines[y] or ""
	local n = buf:str_len(s)
	if x < 1 or x > n then return true end
	local ch = buf:str_char_at(s, x)
	return ch == " " or ch == "\t"
end

-- class: 0 = blank, 1 = keyword char, 2 = other non-blank; if isWORD => collapse to 1
local function _class_of(buf, lines, y, x, isWORD, kwset)
	if _is_blank(buf, lines, y, x) then return 0 end
	if isWORD then return 1 end
	local cp = buf:str_codepoint_at(lines[y], x)
	return kwset[cp] and 1 or 2
end

local function _skip_blanks_fwd(buf, lines, y, x)
	while y do
		if not _is_blank(buf, lines, y, x) then return y, x end
		y, x = _fwd(buf, lines, y, x)
	end
	return nil, nil
end

local function _skip_blanks_back(buf, lines, y, x)
	while y do
		if not _is_blank(buf, lines, y, x) then return y, x end
		y, x = _back(buf, lines, y, x)
	end
	return nil, nil
end

local function _advance_past_run(buf, lines, y, x, isWORD, kwset, c0)
	local yy, xx = y, x
	while true do
		local ny, nx = _fwd(buf, lines, yy, xx)
		if not ny or _class_of(buf, lines, ny, nx, isWORD, kwset) ~= c0 then return ny, nx end
		yy, xx = ny, nx
	end
end

-- ---------- one-step motions ----------
local function _next_once(buf, lines, y, x, isWORD, to_end, kwset)
	if to_end then
		-- e/E: to end of current/next run; does not stop on empty lines
		local yy, xx = _skip_blanks_fwd(buf, lines, y, x)
		if not yy then return nil, nil end
		local c0 = _class_of(buf, lines, yy, xx, isWORD, kwset)
		local ty, tx = _fwd(buf, lines, yy, xx)
		local at_run_end = (not ty) or (_class_of(buf, lines, ty, tx, isWORD, kwset) ~= c0)
		if at_run_end then
			yy, xx = _skip_blanks_fwd(buf, lines, ty, tx)
			if not yy then return nil, nil end
			c0 = _class_of(buf, lines, yy, xx, isWORD, kwset)
		end
		while true do
			local ny, nx = _fwd(buf, lines, yy, xx)
			if not ny or _class_of(buf, lines, ny, nx, isWORD, kwset) ~= c0 then return yy, xx end
			yy, xx = ny, nx
		end
	else
		-- w/W: to start of next run
		local c0 = _class_of(buf, lines, y, x, isWORD, kwset)
		if c0 == 0 then
			return _skip_blanks_fwd(buf, lines, y, x) -- land on first non-blank
		else
			local ny, nx = _advance_past_run(buf, lines, y, x, isWORD, kwset, c0)
			if not ny then return nil, nil end
			return _skip_blanks_fwd(buf, lines, ny, nx)
		end
	end
end

local function _rewind_over_same_run_left(buf, lines, y, x, isWORD, kwset)
	local c0 = _class_of(buf, lines, y, x, isWORD, kwset)
	if c0 == 0 then return y, x end
	local yy, xx = y, x
	while true do
		local py, px = _back(buf, lines, yy, xx)
		if not py then return nil, nil end
		if _class_of(buf, lines, py, px, isWORD, kwset) ~= c0 then
			-- (py,px) is outside the run we started in (likely blank or a different run)
			return py, px
		end
		yy, xx = py, px
	end
end

-- REPLACED: full implementation with correct ge/gE semantics
local function _prev_once(buf, lines, y, x, isWORD, to_end, kwset)
	if to_end then
		-- ge/gE: move to the *end of the previous* run.
		-- If currently inside (or at the end of) a run, exclude it entirely.
		local yy, xx = y, x
		local ccur = _class_of(buf, lines, yy, xx, isWORD, kwset)

		if ccur ~= 0 then
			-- In a run: rewind past the *entire* current run to its left boundary.
			yy, xx = _rewind_over_same_run_left(buf, lines, yy, xx, isWORD, kwset)
			if not yy then return nil, nil end
		else
			-- On blank: start from the immediately preceding character.
			yy, xx = _back(buf, lines, yy, xx)
			if not yy then return nil, nil end
		end

		-- Skip any blanks to the left to arrive at the previous run (if any).
		yy, xx = _skip_blanks_back(buf, lines, yy, xx)
		if not yy then return nil, nil end

		-- Walk right to the *last* char of that run.
		while true do
			local ny, nx = _fwd(buf, lines, yy, xx)
			if not ny or _class_of(buf, lines, ny, nx, isWORD, kwset) ~= _class_of(buf, lines, yy, xx, isWORD, kwset) then
				return yy, xx
			end
			yy, xx = ny, nx
		end
	else
		-- b/B: move to the *start of the previous* run.
		-- If at a start already, go to the start of the prior run.
		local yy, xx = _back(buf, lines, y, x)
		if not yy then return nil, nil end

		-- Skip blanks to the left.
		yy, xx = _skip_blanks_back(buf, lines, yy, xx)
		if not yy then return nil, nil end

		-- Walk left to the *first* char of this run.
		while true do
			local py, px = _back(buf, lines, yy, xx)
			if not py or _class_of(buf, lines, py, px, isWORD, kwset) ~= _class_of(buf, lines, yy, xx, isWORD, kwset) then
				return yy, xx
			end
			yy, xx = py, px
		end
	end
end


-- ---------- public API ----------
function WordNav.posNext(win, isWORD, to_end, count, y, x)
	isWORD      = not not isWORD
	to_end      = not not to_end
	y           = y or win.cursory
	x           = x or win.cursorx

	local buf = win.buffer
	local lines = buf:lines_ref(true)
	if #lines == 0 then return nil end
	local kwset = _build_iskeyword_set(buf)

	for _ = 1, count do
		y, x = _next_once(buf, lines, y, x, isWORD, to_end, kwset)
		if not y then return nil end
	end
	return y, x
end

function WordNav.posPrev(win, isWORD, to_end, count, y, x)
	isWORD      = not not isWORD
	to_end      = not not to_end
	y           = y or win.cursory
	x           = x or win.cursorx

	local buf = win.buffer
	local lines = buf:lines_ref(true)
	if #lines == 0 then return nil end
	local kwset = _build_iskeyword_set(buf)

	for _ = 1, count do
		y, x = _prev_once(buf, lines, y, x, isWORD, to_end, kwset)
		if not y then return nil end
	end
	return y, x
end

-- Get the word/WORD run under the cursor.
-- Returns: line, start_col1, end_col1  (inclusive column bounds within that line)
-- If the cursor is on blank/whitespace or outside any text, returns nil.
-- isWORD=false respects 'iskeyword'; true treats contiguous non-blanks as a WORD.
function WordNav.wordUnder(win, isWORD, y, x)
	isWORD = not not isWORD
	y = y or win.cursory
	x = x or win.cursorx

	local buf = win.buffer
	local lines = buf:lines_ref(true)
	if #lines == 0 then return nil end
	if y < 1 or y > #lines then return nil end
	local line = lines[y] or ""
	local linelen = buf:str_len(line)
	if linelen == 0 then return nil end
	if x < 1 then x = 1 end
	if x > linelen then x = linelen end

	local kwset = _build_iskeyword_set(buf)
	if _is_blank(buf, lines, y, x) then return nil end

	local c0 = _class_of(buf, lines, y, x, isWORD, kwset)
	if c0 == 0 then return nil end

	-- Expand left (same line only)
	local sx = x
	while sx > 1 and _class_of(buf, lines, y, sx - 1, isWORD, kwset) == c0 do
		sx = sx - 1
	end
	-- Expand right (same line only)
	local ex = x
	while ex < linelen and _class_of(buf, lines, y, ex + 1, isWORD, kwset) == c0 do
		ex = ex + 1
	end

	return y, sx, ex
end

return WordNav
