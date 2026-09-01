// luaparse smoke test: every shipped .lua must parse.
//   npm i luaparse && node tools/syntax_check.js
const fs = require("fs");
const path = require("path");
const parser = require("luaparse");

const root = path.join(__dirname, "..");
const manifest = fs.readFileSync(path.join(root, "incha.txt"), "utf8")
  .split("\n").map((l) => l.trim())
  .filter((l) => l.endsWith(".lua") && !l.startsWith("##"));

let bad = 0;
for (const rel of manifest) {
  const file = path.join(root, rel);
  if (!fs.existsSync(file)) { console.log(`MISSING ${rel}`); bad++; continue; }
  try {
    parser.parse(fs.readFileSync(file, "utf8"), { luaVersion: "5.1" });
  } catch (e) {
    console.log(`SYNTAX FAIL ${rel} -> ${e.message}`);
    bad++;
  }
}
console.log(`files: ${manifest.length}  failures: ${bad}`);
process.exit(bad ? 1 : 0);
