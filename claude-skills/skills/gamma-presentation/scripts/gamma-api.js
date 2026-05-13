#!/usr/bin/env node
// Gamma API wrapper for generating presentations and documents from markdown.
//
// Usage:
//   node gamma-api.js generate <file.md>   — generate from markdown + frontmatter
//   node gamma-api.js folders              — list workspace folders

const fs = require("fs");
const path = require("path");
const { execSync } = require("child_process");

const API_BASE = "https://public-api.gamma.app/v1.0";

function getApiKey() {
  const key = process.env.GAMMA_API_KEY;
  if (!key) {
    console.error(
      "Error: GAMMA_API_KEY is not set.\n" +
        "Set it in your shell profile (~/.zshrc.user or ~/.bashrc):\n" +
        "  export GAMMA_API_KEY=your-api-key"
    );
    process.exit(1);
  }
  return key;
}

function parseFrontmatter(content) {
  const match = content.match(/^---\s*\n([\s\S]*?)\n---\s*\n/);
  if (!match) return { frontmatter: {}, body: content, raw: "" };

  const raw = match[1];
  const body = content.slice(match[0].length);
  const frontmatter = {};

  let currentKey = null;
  let indent = 0;
  let parent = frontmatter;

  for (const line of raw.split("\n")) {
    const keyMatch = line.match(/^(\s*)([A-Za-z_][A-Za-z0-9_-]*)\s*:\s*(.*)/);
    if (!keyMatch) continue;

    const spaces = keyMatch[1].length;
    const key = keyMatch[2];
    let value = keyMatch[3].trim();

    if (value === "") {
      if (spaces === 0) {
        frontmatter[key] = {};
        parent = frontmatter[key];
        currentKey = key;
        indent = 2;
      }
    } else {
      if (value === "true") value = true;
      else if (value === "false") value = false;
      else if (/^\d+$/.test(value)) value = parseInt(value, 10);

      if (spaces >= indent && currentKey && parent !== frontmatter) {
        parent[key] = value;
      } else {
        frontmatter[key] = value;
        currentKey = null;
        parent = frontmatter;
        indent = 0;
      }
    }
  }

  return { frontmatter, body, raw };
}

function getGitRepoName() {
  try {
    const url = execSync("git remote get-url origin 2>/dev/null", {
      encoding: "utf8",
    }).trim();
    const match = url.match(/\/([^/]+?)(?:\.git)?$/);
    return match ? match[1] : null;
  } catch {
    return null;
  }
}

async function apiFetch(endpoint, options = {}) {
  const key = getApiKey();
  const url = `${API_BASE}${endpoint}`;

  const res = await fetch(url, {
    ...options,
    headers: {
      Authorization: `Bearer ${key}`,
      "Content-Type": "application/json",
      ...options.headers,
    },
  });

  if (!res.ok) {
    const text = await res.text();
    let detail = text;
    try {
      detail = JSON.parse(text).message || text;
    } catch {}
    console.error(`API error (${res.status}): ${detail}`);
    process.exit(1);
  }

  return res.json();
}

async function listFolders() {
  const data = await apiFetch("/folders");
  const folders = Array.isArray(data) ? data : data.folders || [];

  if (folders.length === 0) {
    console.log("No folders found in your Gamma workspace.");
    return;
  }

  console.log("Gamma workspace folders:\n");
  for (const f of folders) {
    console.log(`  ${f.name || f.title || "(untitled)"}  →  ${f.id}`);
  }
}

async function autoDetectFolder() {
  const repoName = getGitRepoName();
  if (!repoName) return null;

  try {
    const data = await apiFetch("/folders");
    const folders = Array.isArray(data) ? data : data.folders || [];
    const match = folders.find(
      (f) =>
        (f.name || f.title || "").toLowerCase() === repoName.toLowerCase()
    );
    if (match) {
      console.log(`Auto-detected folder: ${match.name || match.title} (${match.id})`);
      return match.id;
    }
  } catch {}
  return null;
}

function writeFrontmatterBack(filePath, content, url) {
  const timestamp = new Date().toISOString();
  const match = content.match(/^---\s*\n([\s\S]*?)\n---\s*\n/);

  if (!match) {
    const newFront = `---\ngamma:\n  generatedUrl: ${url}\n  generatedAt: ${timestamp}\n---\n\n`;
    fs.writeFileSync(filePath, newFront + content, "utf8");
    return;
  }

  let fm = match[1];
  // Remove existing generatedUrl/generatedAt lines
  fm = fm
    .split("\n")
    .filter((l) => !l.match(/^\s*generated(Url|At)\s*:/))
    .join("\n");

  // Append under gamma: block or at top level
  if (fm.includes("gamma:")) {
    const lines = fm.split("\n");
    const gammaIdx = lines.findIndex((l) => /^gamma\s*:/.test(l));
    let insertIdx = gammaIdx + 1;
    while (
      insertIdx < lines.length &&
      lines[insertIdx].match(/^\s+[A-Za-z]/)
    ) {
      insertIdx++;
    }
    lines.splice(
      insertIdx,
      0,
      `  generatedUrl: ${url}`,
      `  generatedAt: ${timestamp}`
    );
    fm = lines.join("\n");
  } else {
    fm += `\ngeneratedUrl: ${url}\ngeneratedAt: ${timestamp}`;
  }

  const rest = content.slice(match[0].length);
  fs.writeFileSync(filePath, `---\n${fm}\n---\n\n${rest}`, "utf8");
}

async function generate(filePath) {
  if (!fs.existsSync(filePath)) {
    console.error(`Error: File not found: ${filePath}`);
    process.exit(1);
  }

  const content = fs.readFileSync(filePath, "utf8");
  const { frontmatter, body } = parseFrontmatter(content);
  const gamma = frontmatter.gamma || {};

  const format = gamma.format || "presentation";
  const textMode = gamma.textMode || "generate";
  const numCards = Math.min(60, Math.max(1, gamma.numCards || 10));
  const textAmount = gamma.textAmount || "medium";
  const language = gamma.language || "en";
  const dimensions = gamma.dimensions || "16x9";
  const themeId = gamma.themeId || undefined;

  let folderId = gamma.folderId || null;
  if (!folderId) {
    folderId = await autoDetectFolder();
  }

  const payload = {
    inputText: body.trim(),
    textMode,
    format,
    numCards,
    textOptions: {
      amount: textAmount,
      language,
    },
    cardOptions: {
      dimensions,
    },
  };

  if (folderId) payload.folderIds = [folderId];
  if (themeId) payload.themeId = themeId;

  const tokenEstimate = Math.ceil(body.length / 4);
  if (tokenEstimate > 100000) {
    console.warn(
      `Warning: Content is ~${tokenEstimate} tokens (max 100,000). Truncating.`
    );
    payload.inputText = body.trim().slice(0, 400000);
  }

  console.log(
    `Generating ${format} (${numCards} cards, ${textMode}, ${language}, ${dimensions})...`
  );

  const data = await apiFetch("/generations", {
    method: "POST",
    body: JSON.stringify(payload),
  });

  const url = data.url || data.generatedUrl || data.link;
  if (url) {
    console.log(`\nGenerated: ${url}`);
    writeFrontmatterBack(filePath, content, url);
    console.log(`Updated frontmatter in ${path.basename(filePath)}`);
  } else {
    console.log("\nGeneration submitted. Response:");
    console.log(JSON.stringify(data, null, 2));
  }
}

async function main() {
  const args = process.argv.slice(2);

  if (args.length === 0 || args[0] === "--help" || args[0] === "-h") {
    console.log(
      "Usage:\n" +
        "  node gamma-api.js generate <file.md>   Generate from markdown\n" +
        "  node gamma-api.js folders               List workspace folders"
    );
    process.exit(0);
  }

  const command = args[0];

  if (command === "folders") {
    await listFolders();
  } else if (command === "generate") {
    if (!args[1]) {
      console.error("Error: No file specified.\nUsage: node gamma-api.js generate <file.md>");
      process.exit(1);
    }
    await generate(path.resolve(args[1]));
  } else {
    console.error(`Unknown command: ${command}`);
    process.exit(1);
  }
}

main().catch((err) => {
  console.error(`Error: ${err.message}`);
  process.exit(1);
});
