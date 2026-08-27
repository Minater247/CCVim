const { execFileSync } = require("child_process");
const fs = require("fs");
const path = require("path");

const ROOT = path.resolve(__dirname, "..");
const INDEX = path.join(ROOT, "nvim.idx");
const ROOTS = ["layout", "lib", "runtime"];

function trackedInstallFiles() {
  const files = execFileSync("git", ["ls-files", "-z", "--", "nvim.lua", ...ROOTS], {
    cwd: ROOT,
    encoding: "utf8",
  });
  return files.split("\0").filter(Boolean);
}

function buildTree(files) {
  const tree = {};
  for (const file of files) {
    let node = tree;
    for (const part of file.split("/")) {
      node[part] ||= {};
      node = node[part];
    }
  }
  return tree;
}

function appendTree(lines, tree, depth) {
  for (const name of Object.keys(tree).sort()) {
    const children = tree[name];
    const isDirectory = Object.keys(children).length > 0;
    lines.push("\t".repeat(depth) + name + (isDirectory ? "/" : ""));
    if (isDirectory) appendTree(lines, children, depth + 1);
  }
}

function buildIndex() {
  const tree = buildTree(trackedInstallFiles());
  const lines = ["nvim.lua"];
  for (const root of ROOTS) {
    if (!tree[root]) throw new Error(`Missing install root: ${root}`);
    lines.push(`${root}/`);
    appendTree(lines, tree[root], 1);
  }
  return `${lines.join("\n")}\n`;
}

fs.writeFileSync(INDEX, buildIndex());
console.log("updated nvim.idx");
