const fs = require("fs");

const file = require.resolve("lua-format/src/luamin.js");
let source = fs.readFileSync(file, "utf8");
let changed = false;

function apply(original, patched) {
  if (source.includes(patched)) return;
  if (!source.includes(original)) {
    throw new Error("Unsupported lua-format version (expected 1.6.1b); update the compatibility patch");
  }
  source = source.replace(original, patched);
  changed = true;
}

const symbols = "    '[', ']', '(','.', '`'";
apply(symbols, symbols + ", '&', '|'");
apply(
  "|| (shit && lastCh == ')' && firstCh == '(')",
  "|| (lastCh == firstCh && (lastCh == '[' || lastCh == ']')) || (shit && lastCh == ')' && firstCh == '(')"
);
apply("expr.Lhs.Type == 'NumberLiteral'", "expr.Lhs.GetLastToken().Type == 'Number'");
const closeBracket = "            stript(expr.Token_CloseBracket)";
apply(
  closeBracket,
  closeBracket + "; joint(expr.Base.GetLastToken(), expr.Token_OpenBracket);"
    + " joint(expr.Token_OpenBracket, expr.Index.GetFirstToken());"
    + " joint(expr.Index.GetLastToken(), expr.Token_CloseBracket)"
);
const entryCloseBracket = "                    stript(entry.Token_CloseBracket)";
apply(
  entryCloseBracket,
  entryCloseBracket + "; joint(entry.Token_OpenBracket, entry.Index.GetFirstToken());"
    + " joint(entry.Index.GetLastToken(), entry.Token_CloseBracket)"
);
if (changed) fs.writeFileSync(file, source);
