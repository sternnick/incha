// Optional syntax pass for the Incha review checks.
// ESO runs a modified Lua 5.1; `luaparse` covers that grammar.
// Usage:  npm i luaparse   &&   node .review/syntax.js <repo-root>
const luaparse = require('luaparse');
const fs = require('fs');
const path = require('path');

const root = process.argv[2] || '.';
const skip = new Set(['.git', '.review']);

function walk(dir, out = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (skip.has(entry.name)) continue;
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full, out);
    else if (entry.name.endsWith('.lua')) out.push(full);
  }
  return out;
}

let failures = 0;
const files = walk(root);
for (const file of files) {
  const src = fs.readFileSync(file, 'utf8');
  let parsed = false;
  for (const version of ['5.1', '5.2', '5.3']) {
    try { luaparse.parse(src, { luaVersion: version }); parsed = true; break; } catch (e) { /* try next */ }
  }
  if (!parsed) {
    try { luaparse.parse(src, {}); parsed = true; } catch (e) {
      failures += 1;
      console.log('SYNTAX FAIL ' + path.relative(root, file) + ' -> ' + String(e.message).split('\n')[0]);
    }
  }
}
console.log('files: ' + files.length + '  syntax failures: ' + failures);
process.exit(failures ? 1 : 0);
