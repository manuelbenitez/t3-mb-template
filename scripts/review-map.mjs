#!/usr/bin/env node
// The only reader of .claude/review-map.yml (the path -> skills -> docs map).
// Zero dependencies, node >= 20. The map is a constrained YAML subset (the
// shape is described at the top of the map); anything outside it is a hard
// parse error, so the gates that shell out here fail closed.
//
//   node scripts/review-map.mjs match <path>...   JSON: rules, skills, pages and flags per path, required_skills
//   node scripts/review-map.mjs lists             JSON: the top-level lists
//   node scripts/review-map.mjs config            the project: block as shell assignments (lib.sh evals it)
//   node scripts/review-map.mjs render <file>     rewrite the marked blocks of a file in project.rendered_files
//   node scripts/review-map.mjs check             exit 1 on a broken map or a stale rendered block
//   REVIEW_MAP_TOP=<dir> runs against another checkout (the hook harness); the default is this script's repo.
//
// Globs follow bash globstar: `**` is zero or more path segments (so `**/*.md`
// matches the root CLAUDE.md), `*` and `?` never cross `/`, everything else is
// literal (parentheses included). Dotfiles are not special.
import { spawnSync } from "node:child_process";
import { existsSync, readFileSync, statSync, writeFileSync } from "node:fs";
import {
  basename,
  dirname,
  isAbsolute,
  join,
  relative,
  resolve,
} from "node:path";
import { fileURLToPath } from "node:url";

export const SCRIPT_TOP = resolve(
  dirname(fileURLToPath(import.meta.url)),
  "..",
);
export const MAP_REL = ".claude/review-map.yml";

export class MapError extends Error {}

// ---- tokenizer -------------------------------------------------------------
// Tokens: key (`name:`), string (double-quoted, no escapes), bare (identifier,
// number, true/false), `-` (list item), and the flow punctuation [ ] { } ,.
// Each token carries its line, column and whether it opens its line (bol).

const WORD = /[A-Za-z0-9_.-]+/y;

export function tokenize(text, file = MAP_REL) {
  const toks = [];
  const n = text.length;
  let i = 0;
  let line = 1;
  let col = 0;
  let bol = true;
  const err = (m) => {
    throw new MapError(`${file}:${line}:${col + 1}: ${m}`);
  };
  const push = (t) => {
    toks.push({ ...t, line, col, bol });
    bol = false;
  };
  while (i < n) {
    const c = text[i];
    if (c === "\t") err("tab; the map is indented with spaces");
    if (c === "\r") {
      i++;
      continue;
    }
    if (c === "\n") {
      i++;
      line++;
      col = 0;
      bol = true;
      continue;
    }
    if (c === " ") {
      i++;
      col++;
      continue;
    }
    if (c === "#") {
      while (i < n && text[i] !== "\n") i++;
      continue;
    }
    if (c === '"') {
      let j = i + 1;
      let s = "";
      for (;;) {
        if (j >= n || text[j] === "\n") err("unterminated string");
        const d = text[j];
        if (d === "\\") err("backslash in a string; the map has no escapes");
        if (d === "\t") err("tab inside a string");
        if (d === '"') break;
        s += d;
        j++;
      }
      push({ type: "string", value: s });
      col += j + 1 - i;
      i = j + 1;
      continue;
    }
    if (c === "'") err("single-quoted string; use double quotes");
    if (c === "|" || c === ">")
      err(`block scalar (${c}); use a double-quoted string`);
    if (c === "&" || c === "*")
      err(`anchor or alias (${c}); the map has neither`);
    if ("[]{},:".includes(c)) {
      push({ type: c });
      i++;
      col++;
      continue;
    }
    if (
      c === "-" &&
      (i + 1 >= n ||
        text[i + 1] === " " ||
        text[i + 1] === "\n" ||
        text[i + 1] === "\r")
    ) {
      push({ type: "-" });
      i++;
      col++;
      continue;
    }
    WORD.lastIndex = i;
    const m = WORD.exec(text);
    if (!m) err(`unexpected character ${JSON.stringify(c)}`);
    const word = m[0];
    const after = i + word.length;
    const nextC = text[after + 1];
    if (
      text[after] === ":" &&
      (after + 1 >= n || nextC === " " || nextC === "\n" || nextC === "\r")
    ) {
      push({ type: "key", value: word });
      col += word.length + 1;
      i = after + 1;
      continue;
    }
    push({ type: "bare", value: word });
    col += word.length;
    i = after;
  }
  return toks;
}

// ---- parser ----------------------------------------------------------------

const TOP_KEYS = {
  version: "int",
  project: "project",
  docs_only: "list",
  never_docs_only: "list",
  lifecycle: "list",
  skills: "skills",
  rules: "rules",
};
// The project: block. Everything a hook needs to know about this repository
// lives here, so a new project edits one file (setup.sh fills repo and
// state_dir). Kinds: string, bool, list (of strings), map (string -> string).
const PROJECT_KEYS = {
  repo: "string",
  state_dir: "string",
  attribution_guard: "bool",
  internal_docs_root: "string",
  user_docs_root: "string",
  docs_pairs: "map",
  docs_exempt: "list",
  user_visible: "list",
  workspaces: "map",
  deps_check: "list",
  deps_smoke: "list",
  lifecycle_inputs: "list",
  lifecycle_suite: "string",
  secret_exempt: "list",
  rendered_files: "list",
};
const SKILL_KEYS = { when: "string", touch: "string", trigger_only: "bool" };
const RULE_KEYS = {
  id: "name",
  paths: "list",
  skills: "names",
  internal_docs: "list",
  user_docs: "list",
};

export function parseMap(text, file = MAP_REL) {
  const toks = tokenize(text, file);
  let p = 0;
  const peek = () => toks[p];
  const where = (t) => (t ? `${file}:${t.line}:${t.col + 1}` : `${file}:EOF`);
  const fail = (t, m) => {
    throw new MapError(`${where(t)}: ${m}`);
  };
  const show = (t) => {
    if (!t) return "end of file";
    if (t.type === "string") return `"${t.value}"`;
    if (t.type === "key") return `${t.value}:`;
    if (t.type === "bare") return t.value;
    return `'${t.type}'`;
  };
  const next = () => {
    const t = toks[p];
    if (!t) fail(undefined, "unexpected end of file");
    p++;
    return t;
  };
  const expect = (type, m) => {
    const t = next();
    if (t.type !== type) fail(t, `${m}, got ${show(t)}`);
    return t;
  };

  function scalar(kind, key) {
    const t = next();
    switch (kind) {
      case "string":
        if (t.type !== "string")
          fail(t, `${key} must be a double-quoted string, got ${show(t)}`);
        return t.value;
      case "bool":
        if (t.type !== "bare" || (t.value !== "true" && t.value !== "false"))
          fail(t, `${key} must be true or false`);
        return t.value === "true";
      case "int":
        if (t.type !== "bare" || !/^\d+$/.test(t.value))
          fail(t, `${key} must be an integer`);
        return Number(t.value);
      default:
        if (t.type !== "bare" && t.type !== "string")
          fail(t, `${key} must be a name, got ${show(t)}`);
        return t.value;
    }
  }

  // [ "a", "b" ] (kind string) or [ a, b ] (kind name); may span lines.
  function flowList(kind, key) {
    expect("[", `${key} must be a flow list [ ... ]`);
    const out = [];
    for (;;) {
      let t = next();
      if (t.type === "]") break;
      if (kind === "string" && t.type !== "string")
        fail(t, `${key} items must be double-quoted strings, got ${show(t)}`);
      if (kind === "name" && t.type !== "bare" && t.type !== "string")
        fail(t, `${key} items must be names, got ${show(t)}`);
      if (out.includes(t.value)) fail(t, `duplicate ${key} item ${show(t)}`);
      out.push(t.value);
      t = next();
      if (t.type === "]") break;
      if (t.type !== ",")
        fail(t, `expected ',' or ']' in ${key}, got ${show(t)}`);
    }
    return out;
  }

  // { when: "...", touch: "...", trigger_only: true }
  function flowMap(allowed, owner) {
    expect("{", `${owner} must be a flow map { ... }`);
    const out = {};
    for (;;) {
      let t = next();
      if (t.type === "}") break;
      if (t.type !== "key")
        fail(t, `expected key: in ${owner}, got ${show(t)}`);
      if (!(t.value in allowed)) fail(t, `unknown key ${t.value} in ${owner}`);
      if (t.value in out) fail(t, `duplicate key ${t.value} in ${owner}`);
      out[t.value] = scalar(allowed[t.value], t.value);
      t = next();
      if (t.type === "}") break;
      if (t.type !== ",")
        fail(t, `expected ',' or '}' in ${owner}, got ${show(t)}`);
    }
    return out;
  }

  // After a block ends only a top-level key (column 1) or the end of file may follow.
  function endOfBlock() {
    const t = peek();
    if (t && !(t.bol && t.col === 0)) fail(t, `unexpected ${show(t)}`);
  }

  // { "glob": "value", ... }; may span lines.
  function flowStringMap(key) {
    expect("{", `${key} must be a flow map { "key": "value", ... }`);
    const out = {};
    for (;;) {
      let t = next();
      if (t.type === "}") break;
      if (t.type !== "string")
        fail(t, `${key} keys must be double-quoted strings, got ${show(t)}`);
      if (t.value in out) fail(t, `duplicate ${key} key ${show(t)}`);
      const k = t.value;
      t = next();
      if (t.type !== ":") fail(t, `expected ':' after ${key} key "${k}"`);
      t = next();
      if (t.type !== "string")
        fail(t, `${key} values must be double-quoted strings, got ${show(t)}`);
      out[k] = t.value;
      t = next();
      if (t.type === "}") break;
      if (t.type !== ",")
        fail(t, `expected ',' or '}' in ${key}, got ${show(t)}`);
    }
    return out;
  }

  function projectBlock() {
    const out = {};
    const first = peek();
    if (!first || !first.bol || first.col === 0)
      fail(first, "project: needs an indented block of key: value entries");
    const indent = first.col;
    while (peek() && peek().bol && peek().col === indent) {
      const t = next();
      if (t.type !== "key")
        fail(t, `expected a project key followed by ':', got ${show(t)}`);
      if (!(t.value in PROJECT_KEYS)) fail(t, `unknown project key ${t.value}`);
      if (t.value in out) fail(t, `duplicate project key ${t.value}`);
      const kind = PROJECT_KEYS[t.value];
      out[t.value] =
        kind === "list"
          ? flowList("string", t.value)
          : kind === "map"
            ? flowStringMap(t.value)
            : scalar(kind, t.value);
    }
    endOfBlock();
    for (const k of Object.keys(PROJECT_KEYS))
      if (!(k in out)) fail(undefined, `project: is missing ${k}:`);
    if (!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(out.repo))
      fail(undefined, `project.repo must be owner/name, got "${out.repo}"`);
    if (!/^[A-Za-z0-9_.-]+$/.test(out.state_dir))
      fail(undefined, `project.state_dir must be a plain directory name`);
    return out;
  }

  function skillsBlock() {
    // An empty map is allowed: a project without review skills yet.
    if (peek() && peek().type === "{") {
      expect("{", "skills");
      expect("}", "skills: {} is the only flow form");
      endOfBlock();
      return {};
    }
    const out = {};
    const first = peek();
    if (!first || !first.bol || first.col === 0)
      fail(
        first,
        "skills: needs an indented block of name: { when: ... } entries",
      );
    const indent = first.col;
    while (peek() && peek().bol && peek().col === indent) {
      const t = next();
      if (t.type !== "key")
        fail(t, `expected a skill name followed by ':', got ${show(t)}`);
      if (t.value in out) fail(t, `duplicate skill ${t.value}`);
      const e = flowMap(SKILL_KEYS, `skill ${t.value}`);
      if (!("when" in e)) fail(t, `skill ${t.value} needs when:`);
      if (e.trigger_only && !e.touch)
        fail(t, `trigger-only skill ${t.value} needs touch: prose`);
      out[t.value] = {
        when: e.when,
        touch: e.touch ?? null,
        trigger_only: e.trigger_only ?? false,
      };
    }
    endOfBlock();
    return out;
  }

  function rulesBlock() {
    const rules = [];
    const first = peek();
    if (!first || !first.bol || first.col === 0 || first.type !== "-")
      fail(first, "rules: needs an indented block list of '- id: ...' items");
    const indent = first.col;
    while (
      peek() &&
      peek().bol &&
      peek().col === indent &&
      peek().type === "-"
    ) {
      const dash = next();
      const k0 = peek();
      if (!k0 || k0.bol || k0.type !== "key")
        fail(k0 ?? dash, "expected '- id: <name>' on the dash line");
      const keyCol = k0.col;
      const rule = {};
      let firstKey = true;
      while (
        peek() &&
        peek().type === "key" &&
        (firstKey ? !peek().bol : peek().bol && peek().col === keyCol)
      ) {
        firstKey = false;
        const t = next();
        if (!(t.value in RULE_KEYS)) fail(t, `unknown rule key ${t.value}`);
        if (t.value in rule)
          fail(t, `duplicate key ${t.value} in rule ${rule.id ?? "?"}`);
        const kind = RULE_KEYS[t.value];
        rule[t.value] =
          kind === "list"
            ? flowList("string", t.value)
            : kind === "names"
              ? flowList("name", t.value)
              : scalar("name", "id");
      }
      for (const k of Object.keys(RULE_KEYS))
        if (!(k in rule)) fail(dash, `rule ${rule.id ?? "?"} is missing ${k}:`);
      if (rule.paths.length === 0) fail(dash, `rule ${rule.id} has no paths`);
      if (rules.some((r) => r.id === rule.id))
        fail(dash, `duplicate rule id ${rule.id}`);
      rules.push(rule);
      const t = peek();
      if (
        t &&
        !(t.bol && (t.col === 0 || (t.col === indent && t.type === "-")))
      )
        fail(t, `unexpected ${show(t)}`);
    }
    endOfBlock();
    return rules;
  }

  const doc = {};
  while (p < toks.length) {
    const t = next();
    if (!t.bol || t.col !== 0 || t.type !== "key")
      fail(t, `expected a top-level key at column 1, got ${show(t)}`);
    if (!(t.value in TOP_KEYS)) fail(t, `unknown top-level key ${t.value}`);
    if (t.value in doc) fail(t, `duplicate top-level key ${t.value}`);
    const kind = TOP_KEYS[t.value];
    if (kind === "list") doc[t.value] = flowList("string", t.value);
    else if (kind === "skills") doc.skills = skillsBlock();
    else if (kind === "project") doc.project = projectBlock();
    else if (kind === "rules") doc.rules = rulesBlock();
    else doc[t.value] = scalar(kind, t.value);
  }
  for (const k of Object.keys(TOP_KEYS))
    if (!(k in doc)) fail(undefined, `missing top-level key ${k}:`);
  if (doc.version !== 1)
    fail(undefined, `version must be 1, got ${doc.version}`);
  for (const r of doc.rules) {
    for (const s of r.skills)
      if (!(s in doc.skills))
        fail(
          undefined,
          `rule ${r.id} names unknown skill ${s} (not in skills:)`,
        );
    for (const d of r.user_docs)
      if (!d.endsWith("/"))
        fail(
          undefined,
          `rule ${r.id}: user_docs "${d}" must be a directory ending in /`,
        );
  }
  for (const [name, s] of Object.entries(doc.skills)) {
    if (!s.touch && !doc.rules.some((r) => r.skills.includes(name)))
      fail(
        undefined,
        `skill ${name} is named by no rule and has no touch: prose`,
      );
  }
  return doc;
}

export function loadMap(top = SCRIPT_TOP) {
  const file = join(top, MAP_REL);
  let text;
  try {
    text = readFileSync(file, "utf8");
  } catch (e) {
    throw new MapError(`cannot read ${file}: ${e.message}`);
  }
  return parseMap(text, MAP_REL);
}

// ---- globs -----------------------------------------------------------------

export function globToRegExp(glob) {
  const segs = glob.split("/");
  let re = "^";
  segs.forEach((s, i) => {
    const last = i === segs.length - 1;
    if (s === "**") {
      re += last ? ".*" : "(?:[^/]+/)*";
      return;
    }
    re += s
      .replace(/[.+^${}()|[\]\\]/g, "\\$&")
      .replace(/\*\*/g, "*")
      .replace(/\*/g, "[^/]*")
      .replace(/\?/g, "[^/]");
    if (!last) re += "/";
  });
  return new RegExp(re + "$");
}

export function globMatch(glob, path) {
  return globToRegExp(glob).test(path);
}

function compile(globs) {
  return globs.map((g) => ({ glob: g, re: globToRegExp(g) }));
}

function anyMatch(compiled, path) {
  return compiled.some((c) => c.re.test(path));
}

// ---- match -----------------------------------------------------------------

export function docsOnlyVerdict(map, path) {
  if (anyMatch(compile(map.never_docs_only), path)) return "never";
  if (anyMatch(compile(map.docs_only), path)) return "docs";
  return "code";
}

export function matchPaths(map, paths) {
  const rules = map.rules.map((r) => ({ r, res: compile(r.paths) }));
  const life = compile(map.lifecycle);
  const pairs = Object.entries(map.project.docs_pairs).map(([g, area]) => ({
    re: globToRegExp(g),
    area,
  }));
  const exempt = compile(map.project.docs_exempt);
  const visible = compile(map.project.user_visible);
  const never = compile(map.never_docs_only);
  const docs = compile(map.docs_only);
  const out = { paths: {}, skills: {}, required_skills: [] };
  const seen = new Set();
  for (const raw of paths) {
    const path = raw.replace(/^\.\//, "");
    const hit = rules
      .filter(({ res }) => anyMatch(res, path))
      .map(({ r }) => r);
    const union = (key) => [...new Set(hit.flatMap((r) => r[key]))];
    const skills = union("skills");
    for (const s of skills) {
      seen.add(s);
      if (!map.skills[s].trigger_only && !out.required_skills.includes(s))
        out.required_skills.push(s);
    }
    out.paths[path] = {
      rules: hit.map((r) => r.id),
      skills,
      internal_docs: union("internal_docs"),
      user_docs: union("user_docs"),
      lifecycle: anyMatch(life, path),
      // Every docs directory a staged change to this path must also touch
      // (the union of the matching pairs; none for a test or story).
      docs_areas: anyMatch(exempt, path)
        ? []
        : [...new Set(pairs.filter((p) => p.re.test(path)).map((p) => p.area))],
      user_visible: !anyMatch(exempt, path) && anyMatch(visible, path),
      docs_only: anyMatch(never, path)
        ? "never"
        : anyMatch(docs, path)
          ? "docs"
          : "code",
    };
  }
  for (const name of Object.keys(map.skills))
    if (seen.has(name)) out.skills[name] = map.skills[name];
  out.required_skills.sort();
  return out;
}

export function lists(map) {
  const { version, docs_only, never_docs_only, lifecycle } = map;
  return { version, docs_only, never_docs_only, lifecycle };
}

// Shell-quoted assignments, one per project key: HOOK_CFG_<KEY>='value'.
// Lists are newline-joined, maps are "key<TAB>value" lines, bools are yes/no.
export function shellConfig(map) {
  const q = (v) => "'" + v.replace(/'/g, "'\\''") + "'";
  const lines = [];
  for (const [k, v] of Object.entries(map.project)) {
    const value = Array.isArray(v)
      ? v.join("\n")
      : typeof v === "boolean"
        ? v
          ? "yes"
          : "no"
        : typeof v === "object"
          ? Object.entries(v)
              .map(([a, b]) => `${a}\t${b}`)
              .join("\n")
          : String(v);
    lines.push(`HOOK_CFG_${k.toUpperCase()}=${q(value)}`);
  }
  return lines.join("\n") + "\n";
}

// ---- render ----------------------------------------------------------------

const code = (s) => "`" + s.replace(/\|/g, "\\|") + "`";
const cell = (s) => s.replace(/\|/g, "\\|");

// The union of the rules' paths naming a skill, in rule order.
export function skillPaths(map, name) {
  return [
    ...new Set(
      map.rules.filter((r) => r.skills.includes(name)).flatMap((r) => r.paths),
    ),
  ];
}

export function renderSkillsTable(map) {
  const rows = ["| Skill | Touch | When |", "| --- | --- | --- |"];
  for (const [name, s] of Object.entries(map.skills)) {
    const touch = s.touch ?? skillPaths(map, name).map(code).join(", ");
    rows.push(`| ${code("/" + name)} | ${cell(touch)} | ${cell(s.when)} |`);
  }
  return rows.join("\n");
}

export function renderApiPagesTable(map) {
  const rows = ["| You're touching… | Read / update |", "| --- | --- |"];
  for (const r of map.rules) {
    const api = r.paths.filter((p) => p.startsWith("apps/api/"));
    if (api.length === 0 || r.internal_docs.length === 0) continue;
    const paths = api.map((p) =>
      code(p.startsWith("apps/api/src/") ? p.slice("apps/api/src/".length) : p),
    );
    rows.push(
      `| ${paths.join(", ")} | ${r.internal_docs.map(code).join(", ")} |`,
    );
  }
  return rows.join("\n");
}

const BLOCKS = { skills: renderSkillsTable, "api-pages": renderApiPagesTable };
const MARKER_RE =
  /<!-- review-map:([a-z-]+) -->[\s\S]*?<!-- \/review-map:\1 -->/g;

// Replaces every marked block in `text` with a fresh render (unformatted).
export function renderBlocks(map, text, file) {
  let count = 0;
  const out = text.replace(MARKER_RE, (_, name) => {
    const fn = BLOCKS[name];
    if (!fn)
      throw new MapError(
        `${file}: unknown block review-map:${name} (known: ${Object.keys(BLOCKS).join(", ")})`,
      );
    count++;
    return `<!-- review-map:${name} -->\n\n${fn(map)}\n\n<!-- /review-map:${name} -->`;
  });
  if (count === 0)
    throw new MapError(`${file}: no <!-- review-map:... --> markers found`);
  return out;
}

export function extractBlocks(text) {
  return [...text.matchAll(MARKER_RE)].map((m) => m[0]);
}

// prettier from this repo's own node_modules, with the file's config path so
// the result equals what format-on-edit.sh would write.
export function prettierFormat(top, rel, input) {
  const r = spawnSync("pnpm", ["exec", "prettier", "--stdin-filepath", rel], {
    cwd: top,
    input,
    encoding: "utf8",
  });
  if (r.error || r.status !== 0) {
    const why = r.error ? r.error.message : (r.stderr || "").trim();
    throw new MapError(
      `prettier failed for ${rel}: ${why} (fix: pnpm install)`,
    );
  }
  return r.stdout;
}

// {current, fresh}: the file's marked blocks as they are and as a fresh render
// (formatted) would leave them, plus the formatted full text.
export function renderFile(map, top, file) {
  const abs = isAbsolute(file) ? file : resolve(top, file);
  const rel = relative(top, abs);
  if (rel.startsWith("..")) throw new MapError(`${file} is outside ${top}`);
  const current = readFileSync(abs, "utf8");
  const fresh = prettierFormat(top, rel, renderBlocks(map, current, rel));
  return {
    abs,
    rel,
    current,
    fresh,
    currentBlocks: extractBlocks(current).join("\n"),
    freshBlocks: extractBlocks(fresh).join("\n"),
  };
}

// ---- check -----------------------------------------------------------------

export function gitLsFiles(top) {
  const r = spawnSync("git", ["-C", top, "ls-files", "-z"], {
    encoding: "utf8",
    maxBuffer: 64 * 1024 * 1024,
  });
  if (r.error || r.status !== 0)
    throw new MapError(
      `git ls-files failed in ${top}: ${r.error ? r.error.message : r.stderr.trim()}`,
    );
  return r.stdout.split("\0").filter(Boolean);
}

const isDocsFile = (f) =>
  f.endsWith(".md") || f.endsWith(".png") || basename(f) === ".gitkeep";

// Pure: the file system and the renderer are injected so the fixtures can run
// without git or prettier. Returns {errors, warnings, infos}.
export function checkMap(map, io) {
  const errors = [];
  const warnings = [];
  const infos = [];
  const files = io.files;
  const matching = (glob) => {
    const re = globToRegExp(glob);
    return files.filter((f) => re.test(f));
  };

  const { internal_docs_root: idocs, user_docs_root: udocs } = map.project;
  for (const list of ["docs_only", "never_docs_only", "lifecycle"]) {
    for (const g of map[list])
      if (matching(g).length === 0)
        errors.push(`${list}: "${g}" matches no tracked file`);
  }
  for (const r of map.rules) {
    for (const g of r.paths)
      if (matching(g).length === 0)
        errors.push(`rule ${r.id}: paths "${g}" matches no tracked file`);
    for (const page of r.internal_docs)
      if (!io.fileExists(join(idocs, page)))
        errors.push(
          `rule ${r.id}: internal_docs "${page}" is not a file under ${idocs}/`,
        );
    for (const dir of r.user_docs)
      if (!udocs)
        errors.push(
          `rule ${r.id}: user_docs "${dir}" given but project.user_docs_root is empty`,
        );
      else if (!io.dirExists(join(udocs, dir)))
        errors.push(
          `rule ${r.id}: user_docs "${dir}" is not a directory under ${udocs}/`,
        );
  }
  for (const [glob, area] of Object.entries(map.project.docs_pairs)) {
    if (matching(glob).length === 0)
      errors.push(`project.docs_pairs: "${glob}" matches no tracked file`);
    if (!area || !area.endsWith("/"))
      errors.push(
        `project.docs_pairs: "${glob}" needs a directory ending in /, got "${area}"`,
      );
    else if (!io.dirExists(area.replace(/\/$/, "")))
      errors.push(`project.docs_pairs: "${area}" is not a directory`);
  }
  for (const [dir] of Object.entries(map.project.workspaces))
    if (!io.fileExists(join(dir, "package.json")))
      errors.push(`project.workspaces: "${dir}" has no package.json`);
  for (const file of map.project.rendered_files) {
    try {
      const { currentBlocks, freshBlocks } = io.render(file);
      if (currentBlocks !== freshBlocks)
        errors.push(
          `${file}: the review-map block is stale; run: node scripts/review-map.mjs render ${file}`,
        );
    } catch (e) {
      if (!(e instanceof MapError)) throw e;
      errors.push(e.message);
    }
  }

  for (const g of map.docs_only) {
    const odd = matching(g).filter((f) => !isDocsFile(f));
    if (odd.length)
      warnings.push(
        `docs_only "${g}" matches ${odd.length} non-md/png/gitkeep file(s), e.g. ${odd.slice(0, 3).join(", ")}`,
      );
  }
  for (const d of map.docs_only) {
    const dm = matching(d);
    for (const nv of map.never_docs_only) {
      const re = globToRegExp(nv);
      const both = dm.filter((f) => re.test(f));
      if (both.length)
        infos.push(
          `docs_only "${d}" and never_docs_only "${nv}" overlap on ${both.length} file(s), e.g. ${both[0]}; never_docs_only wins`,
        );
    }
  }
  return { errors, warnings, infos };
}

export function realIo(map, top) {
  return {
    files: gitLsFiles(top),
    fileExists: (rel) =>
      existsSync(join(top, rel)) && statSync(join(top, rel)).isFile(),
    dirExists: (rel) =>
      existsSync(join(top, rel)) && statSync(join(top, rel)).isDirectory(),
    render: (file) => renderFile(map, top, file),
  };
}

// ---- cli -------------------------------------------------------------------

const USAGE = `usage: node scripts/review-map.mjs match <path>... | lists | config | render <file> | check`;

export function main(argv, top = SCRIPT_TOP) {
  const [cmd, ...args] = argv;
  const map = loadMap(top);
  switch (cmd) {
    case "match":
      process.stdout.write(
        JSON.stringify(matchPaths(map, args), null, 2) + "\n",
      );
      return 0;
    case "lists":
      process.stdout.write(JSON.stringify(lists(map), null, 2) + "\n");
      return 0;
    case "config":
      process.stdout.write(shellConfig(map));
      return 0;
    case "render": {
      if (args.length !== 1) throw new MapError(USAGE);
      const { abs, rel, current, fresh } = renderFile(map, top, args[0]);
      if (current === fresh) {
        process.stderr.write(`${rel}: unchanged\n`);
      } else {
        writeFileSync(abs, fresh);
        process.stderr.write(`${rel}: rendered\n`);
      }
      return 0;
    }
    case "check": {
      const { errors, warnings, infos } = checkMap(map, realIo(map, top));
      for (const m of errors) process.stdout.write(`error: ${m}\n`);
      for (const m of warnings) process.stdout.write(`warning: ${m}\n`);
      for (const m of infos) process.stdout.write(`info: ${m}\n`);
      process.stdout.write(
        `review-map: ${errors.length} error(s), ${warnings.length} warning(s)\n`,
      );
      return errors.length ? 1 : 0;
    }
    default:
      throw new MapError(USAGE);
  }
}

if (
  process.argv[1] &&
  resolve(process.argv[1]) === fileURLToPath(import.meta.url)
) {
  // process.exitCode, never process.exit(): exit() kills the process before a
  // PIPED stdout drains, so a consumer (ai-review.sh | jq) got exactly 64 KB of
  // a larger `match` result, failed to parse it, and fell back to requiring
  // only `review` — the gate failed open on every large branch.
  try {
    process.exitCode = main(
      process.argv.slice(2),
      process.env.REVIEW_MAP_TOP
        ? resolve(process.env.REVIEW_MAP_TOP)
        : SCRIPT_TOP,
    );
  } catch (e) {
    if (e instanceof MapError) {
      process.stderr.write(`review-map: ${e.message}\n`);
      process.exitCode = 1;
    } else {
      throw e;
    }
  }
}
