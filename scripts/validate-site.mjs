import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";

const root = process.cwd();
const pagesDir = path.join(root, "pages");
const jsDir = path.join(root, "js");
const htmlFiles = [
  path.join(root, "index.html"),
  ...fs.readdirSync(pagesDir).filter(name => name.endsWith(".html")).map(name => path.join(pagesDir, name))
];
const jsFiles = fs.readdirSync(jsDir).filter(name => name.endsWith(".js")).map(name => path.join(jsDir, name));
const failures = [];

function checkJs(source, label) {
  try {
    new vm.Script(source, { filename: label });
  } catch (error) {
    failures.push(label + ": " + error.name + ": " + error.message);
  }
}

function inlineScripts(html) {
  const result = [];
  const openTag = "<" + "script";
  const closeTag = "</" + "script>";
  let cursor = 0;
  while (cursor < html.length) {
    const start = html.indexOf(openTag, cursor);
    if (start < 0) break;
    const openEnd = html.indexOf(">", start);
    if (openEnd < 0) break;
    const end = html.indexOf(closeTag, openEnd + 1);
    if (end < 0) break;
    const attributes = html.slice(start, openEnd);
    if (!/\bsrc\s*=/i.test(attributes)) result.push(html.slice(openEnd + 1, end));
    cursor = end + closeTag.length;
  }
  return result;
}

function localReferences(html) {
  const refs = [];
  const pattern = /\b(?:href|src)\s*=\s*["']([^"']+)["']/gi;
  let match;
  while ((match = pattern.exec(html)) !== null) {
    const ref = match[1];
    if (!/^(https?:|mailto:|tel:|#|data:|javascript:)/i.test(ref)) refs.push(ref);
  }
  return refs;
}

for (const file of htmlFiles) {
  const source = fs.readFileSync(file, "utf8");
  const label = path.relative(root, file);
  inlineScripts(source).forEach((script, index) => {
    if (script.trim()) checkJs(script, label + " inline script " + (index + 1));
  });
  for (const ref of localReferences(source)) {
    const clean = ref.split("?")[0].split("#")[0];
    if (!clean) continue;
    const target = path.resolve(path.dirname(file), clean);
    if (!fs.existsSync(target)) failures.push(label + ": missing local asset " + ref);
  }
}

for (const file of jsFiles) checkJs(fs.readFileSync(file, "utf8"), path.relative(root, file));

if (failures.length) {
  console.error("Site validation failed:");
  failures.forEach(failure => console.error(" - " + failure));
  process.exit(1);
}

console.log("Site validation passed for " + htmlFiles.length + " HTML files and " + jsFiles.length + " JavaScript files.");
