#!/usr/bin/env python3
"""Compile a Vimscript file with vim.lib.excmd.compiler.

Usage:
  python vim/tests/compile_vimscript.py path/to/file.vim
  python vim/tests/compile_vimscript.py path/to/file.vim -o /tmp/out.lua --stats
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path


def _lua_long_string(value: str) -> str:
    if "]]" not in value:
        return f"[[{value}]]"
    level = 1
    while True:
        marker = "]" + ("=" * level) + "]"
        if marker not in value:
            return "[" + ("=" * level) + "[" + value + marker
        level += 1


def build_lua_runner(input_path: Path, output_path: Path | None, script_ctx: str) -> str:
    inp = _lua_long_string(str(input_path))
    out = _lua_long_string(str(output_path)) if output_path else "nil"
    ctx = _lua_long_string(script_ctx)
    return f"""
local input_path = {inp}
local output_path = {out}
local script_ctx = {ctx}

local function read_all(path)
  local f, err = io.open(path, "rb")
  if not f then
    io.stderr:write("failed to read input: " .. tostring(err) .. "\\n")
    os.exit(1)
  end
  local data = f:read("*a")
  f:close()
  return data
end

local function write_all(path, data)
  local f, err = io.open(path, "wb")
  if not f then
    io.stderr:write("failed to write output: " .. tostring(err) .. "\\n")
    os.exit(1)
  end
  f:write(data)
  f:close()
end

local MockEnv = dofile("vim/tests/test_mocks.lua")
local mock = MockEnv.setup({{}})
local Compiler = mock.loadModule("vim.lib.excmd.compiler")
local Runtime = mock.loadModule("vim.lib.excmd.runtime")
local Scopes = mock.loadModule("vim.lib.luaapi.scopes")

local script = read_all(input_path)
local durable = Runtime.CaptureDurableScriptState({{ script_ctx = script_ctx }}) or {{ s = {{}}, funcs = {{}} }}
durable.g = durable.g or Scopes._g

local state = Runtime.MakeRuntimeState(durable)
state.g = durable.g

local code, err = Compiler.compile_script(script, {{ state = state }})
if not code then
    io.stderr:write("compile failed: " .. tostring(err) .. "\\n")
  os.exit(2)
end

if output_path and output_path ~= "" then
  write_all(output_path, code)
else
  io.write(code)
end
"""


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Compile a Vimscript file with the JIT compiler")
    parser.add_argument("input", type=Path, help="Path to input Vimscript file")
    parser.add_argument("-o", "--output", type=Path, help="Write compiled Lua to this file")
    parser.add_argument(
        "--script-ctx",
        default=None,
        help="Optional script context path used for durable script state (defaults to input path)",
    )
    parser.add_argument("--stats", action="store_true", help="Print input/output size stats to stderr")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    script_path = args.input.expanduser().resolve()
    if not script_path.exists() or not script_path.is_file():
        print(f"input file not found: {script_path}", file=sys.stderr)
        return 1

    workspace = Path(__file__).resolve().parents[2]
    script_ctx = args.script_ctx or str(script_path)

    lua_runner = build_lua_runner(script_path, args.output, script_ctx)

    proc = subprocess.run(
        ["lua", "-"],
        input=lua_runner,
        text=True,
        cwd=str(workspace),
        capture_output=True,
    )

    if proc.stdout:
        sys.stdout.write(proc.stdout)
    if proc.stderr:
        sys.stderr.write(proc.stderr)

    if proc.returncode != 0:
        return proc.returncode

    if args.stats:
        input_bytes = script_path.stat().st_size
        if args.output:
            output_bytes = args.output.expanduser().resolve().stat().st_size
        else:
            output_bytes = len(proc.stdout.encode("utf-8"))
        print(
            f"compiled: input={input_bytes} bytes, output={output_bytes} bytes",
            file=sys.stderr,
        )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
