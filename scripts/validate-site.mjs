import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";

const root = process.cwd();
const pagesDir = path.join(root, "pages");
const files = [
  path.join(root, "index.html"),
  ...fs.readdirSync(pagesDir)
    .filter(name => name.endsWith(".html"))
    .map(name => path.join(pagesDir, name)),
  path.join(root, "js", "app.js"),
  path.join(root, "js", "config.js")
];

const failures = [];

function checkJs(source, label) {
  try {
    new Function(source);
  } catch (error) {
    failures.push(`${label}: ${error.name}: ${error.message}`);
  }
}

for (const file of files) {
  const source = fs.readFileSync(file, "utf8");
  const label = path.relative(root, file);

  if (file.endsWith(".html")) {
    const scripts = [...source.matchAll(/<script(?:\\s[^>]*)?>([\\s\\S]*?)<\\/script>/gi)];
    scripts.forEach((match, index) => {
      if (match[1].trim()) checkJs(match[1], `${label} inline script ${index + 1}`);
    });

    const refs = [...source.matchAll(/(?:href|src)=["']([^"']+)["']/gi)]
      .map(m => m[1])
      .filter(ref => !/^(https?:|mailto:|tel:|#|data:|javascript:)/i.test(ref));

    for (const ref of refs) {
      const clean = ref.split("?")[0].split("#")[0];
      const target = path.resolve(path.dirname(file), clean);
      if (!fs.existsSync(target)) failures.push(`${label}: missing local asset ${ref}`);
    }
  } else {
    checkJs(source, label);
  }
}

if (failures.length) {
  console.error("Site validation failed:");
  for (const failure of failures) console.error(" - " + failure);
  process.exit(1);
}

console.log(`Site validation passed for ${files.length} files.`);
