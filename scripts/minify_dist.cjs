const fs = require("fs/promises");
const path = require("path");
const luamin = require("lua-format");

const ROOT = path.resolve(__dirname, "..");
const DIST = path.join(ROOT, "dist");

const INCLUDE_PATHS = [
  "instui.lua",
  "nvim.lua",
  "vim_installer.lua",
  "layout",
  "lib",
  "runtime",
];

async function collectLuaFiles(absPath, files) {
  const stat = await fs.lstat(absPath);

  if (stat.isFile()) {
    if (absPath.endsWith(".lua")) {
      files.add(absPath);
    }
    return;
  }

  if (!stat.isDirectory()) {
    return;
  }

  const entries = await fs.readdir(absPath, { withFileTypes: true });

  for (const entry of entries) {
    const child = path.join(absPath, entry.name);

    if (entry.isDirectory()) {
      await collectLuaFiles(child, files);
      continue;
    }

    if (entry.isFile() && entry.name.endsWith(".lua")) {
      files.add(child);
    }
  }
}

async function main() {
  await fs.rm(DIST, { recursive: true, force: true });
  await fs.mkdir(DIST, { recursive: true });

  const files = new Set();

  for (const relInput of INCLUDE_PATHS) {
    if (typeof relInput !== "string" || relInput.trim() === "") {
      throw new Error(`Invalid include path: ${relInput}`);
    }

    const normalized = path.normalize(relInput);

    if (path.isAbsolute(normalized)) {
      throw new Error(`Include path must be relative: ${relInput}`);
    }

    if (normalized === ".." || normalized.startsWith(`..${path.sep}`)) {
      throw new Error(`Include path escapes repo root: ${relInput}`);
    }

    if (normalized === "dist" || normalized.startsWith(`dist${path.sep}`)) {
      throw new Error(`Do not include dist in INCLUDE_PATHS: ${relInput}`);
    }

    const absInput = path.resolve(ROOT, normalized);

    try {
      await fs.access(absInput);
    } catch {
      throw new Error(`Include path does not exist: ${relInput}`);
    }

    await collectLuaFiles(absInput, files);
  }

  const sortedFiles = Array.from(files).sort((a, b) => a.localeCompare(b));

  let count = 0;

  for (const file of sortedFiles) {
    const rel = path.relative(ROOT, file);
    const out = path.join(DIST, rel);

    const src = await fs.readFile(file, "utf8");

    const min = luamin.Minify(src, {
      RenameVariables: true,
      RenameGlobals: false,
      Indentation: "\t",
    });

    await fs.mkdir(path.dirname(out), { recursive: true });
    await fs.writeFile(out, min, "utf8");

    count++;
    console.log(`minified: ${rel}`);
  }

  console.log(`done: ${count} Lua file(s) -> dist/`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
