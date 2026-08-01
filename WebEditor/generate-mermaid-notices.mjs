import fs from "node:fs";
import path from "node:path";

const [metafilePath, outputPath] = process.argv.slice(2);
if (!metafilePath || !outputPath) {
  throw new Error("Usage: node generate-mermaid-notices.mjs <esbuild-metafile> <output>");
}

function packageRootForInput(input) {
  const segments = input.replaceAll("\\", "/").split("/");
  let nodeModulesIndex = -1;
  for (let index = 0; index < segments.length; index += 1) {
    if (segments[index] === "node_modules") nodeModulesIndex = index;
  }
  if (nodeModulesIndex < 0 || nodeModulesIndex + 1 >= segments.length) return null;
  const packageEnd = segments[nodeModulesIndex + 1].startsWith("@")
    ? nodeModulesIndex + 3
    : nodeModulesIndex + 2;
  if (packageEnd > segments.length) return null;
  return segments.slice(0, packageEnd).join("/");
}

function noticeFiles(packageRoot) {
  return fs.readdirSync(packageRoot, {withFileTypes: true})
    .filter((entry) => entry.isFile())
    .map((entry) => entry.name)
    .filter((name) => /^(?:licen[cs]e|copying|notice)(?:[._-].*)?$/i.test(name))
    .sort((left, right) => left.localeCompare(right, "en"));
}

const metafile = JSON.parse(fs.readFileSync(metafilePath, "utf8"));
const packageRoots = new Set(
  Object.keys(metafile.inputs)
    .map(packageRootForInput)
    .filter((value) => value !== null),
);
const packages = [];
for (const packageRoot of packageRoots) {
  const packageJSON = JSON.parse(fs.readFileSync(path.join(packageRoot, "package.json"), "utf8"));
  const files = noticeFiles(packageRoot);
  if (!files.some((name) => /^(?:licen[cs]e|copying)/i.test(name))) {
    throw new Error(`Bundled package ${packageJSON.name}@${packageJSON.version} has no retained license file.`);
  }
  packages.push({
    name: packageJSON.name,
    version: packageJSON.version,
    declaredLicense: packageJSON.license == null
      ? "not declared"
      : typeof packageJSON.license === "string"
        ? packageJSON.license
        : JSON.stringify(packageJSON.license),
    files: files.map((name) => ({
      name,
      text: fs.readFileSync(path.join(packageRoot, name), "utf8").trim(),
    })),
  });
}
packages.sort((left, right) =>
  left.name.localeCompare(right.name, "en") || left.version.localeCompare(right.version, "en"));
if (!packages.some((entry) => entry.name === "mermaid")) {
  throw new Error("The Mermaid runtime metafile did not include the Mermaid package.");
}

const uniquePackages = packages.filter((entry, index) =>
  index === 0
    || entry.name !== packages[index - 1].name
    || entry.version !== packages[index - 1].version,
);
const sections = uniquePackages.map((entry) => [
  "=".repeat(78),
  `${entry.name} ${entry.version}`,
  `Declared license: ${entry.declaredLicense}`,
  ...entry.files.flatMap((file) => ["", `--- ${file.name} ---`, "", file.text]),
].join("\n"));
const notice = [
  "Scholium bundled Mermaid runtime notices",
  "",
  "This deterministic file covers the packages that esbuild includes in",
  "Scholium's offline Mermaid runtime. Regenerate it with build-editor.sh.",
  "",
  ...sections,
  "",
].join("\n");

fs.writeFileSync(outputPath, notice, "utf8");
