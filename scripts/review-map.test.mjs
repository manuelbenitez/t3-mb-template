// Fixtures for scripts/review-map.mjs: the constrained parser, the project:
// block, the glob matcher, match/render/config, and checkMap with an injected
// file system.
//
//   node scripts/review-map.test.mjs

import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { test } from "node:test";

import {
  checkMap,
  docsOnlyVerdict,
  globMatch,
  loadMap,
  MapError,
  matchPaths,
  parseMap,
  renderApiPagesTable,
  renderBlocks,
  renderSkillsTable,
  SCRIPT_TOP,
  shellConfig,
  skillPaths,
} from "./review-map.mjs";

const PROJECT = `project:
  repo: "acme/app"
  state_dir: "app-hooks"
  attribution_guard: true
  internal_docs_root: "internal-docs"
  user_docs_root: "apps/docs/en"
  docs_pairs: { "apps/api/src/**": "internal-docs/", "apps/nextjs/src/**": "internal-docs/frontend/" }
  docs_exempt: ["**/*.spec.ts", "**/*.test.tsx"]
  user_visible: ["apps/nextjs/src/app/**"]
  workspaces: { "apps/api": "@acme/api", "apps/nextjs": "@acme/nextjs" }
  deps_check: ["pnpm install --frozen-lockfile --lockfile-only --offline", "pnpm typecheck"]
  deps_smoke: ["pnpm --filter @acme/api build"]
  lifecycle_inputs: ["apps/api", "pnpm-lock.yaml"]
  lifecycle_suite: "pnpm --filter @acme/api test:e2e"
  secret_exempt: ["*.md", "it's*"]
  rendered_files: ["CLAUDE.md"]
`;

const BASE = `# a comment line
version: 1
${PROJECT}docs_only: ["**/*.md", "apps/docs/en/**/*.md"]
never_docs_only: [".claude/**", "**/*.ts"]   # trailing comment
lifecycle: ["apps/api/src/billing/**"]
skills:
  billing-check: { when: "rates, totals, rounding" }
  portal-review: { when: "an amount a user reads" }
  security-check: { when: "secrets in logs", touch: "any file under apps/api/src/ (all of it)", trigger_only: true }
rules:
  - id: billing
    paths: ["apps/api/src/billing/**",
            "apps/api/src/math/rates*.ts"]
    skills: [billing-check]
    internal_docs: ["architecture/billing.md"]
    user_docs: ["billing/"]
  - id: portal-billing
    paths: ["apps/nextjs/src/app/(app)/billing/**"]
    skills: [portal-review]
    internal_docs: ["frontend/README.md # not a comment"]
    user_docs: ["billing/"]
  - id: api-any
    paths: ["apps/api/src/**"]
    skills: [security-check]
    internal_docs: []
    user_docs: []
`;

const parseErr = (text, re) =>
  assert.throws(
    () => parseMap(text, "fixture.yml"),
    (e) => e instanceof MapError && re.test(e.message),
    `expected ${re}`,
  );

test("parses the constrained shape", () => {
  const m = parseMap(BASE, "fixture.yml");
  assert.equal(m.version, 1);
  assert.equal(m.skills["billing-check"].when, "rates, totals, rounding"); // comma inside when:
  assert.equal(m.skills["billing-check"].touch, null);
  assert.equal(m.skills["billing-check"].trigger_only, false);
  assert.equal(m.skills["security-check"].trigger_only, true);
  assert.equal(
    m.skills["security-check"].touch,
    "any file under apps/api/src/ (all of it)",
  );
  assert.deepEqual(m.never_docs_only, [".claude/**", "**/*.ts"]); // comment after a flow list
  assert.deepEqual(m.rules[0].paths, [
    "apps/api/src/billing/**",
    "apps/api/src/math/rates*.ts",
  ]); // multi-line
  assert.equal(m.rules[1].paths[0], "apps/nextjs/src/app/(app)/billing/**"); // parentheses
  assert.equal(
    m.rules[1].internal_docs[0],
    "frontend/README.md # not a comment",
  ); // # inside a string
  assert.deepEqual(m.rules[2].internal_docs, []);
  assert.deepEqual(Object.keys(m.skills), [
    "billing-check",
    "portal-review",
    "security-check",
  ]);
});

test("parses the project: block", () => {
  const p = parseMap(BASE, "fixture.yml").project;
  assert.equal(p.repo, "acme/app");
  assert.equal(p.attribution_guard, true);
  assert.equal(p.user_docs_root, "apps/docs/en");
  assert.deepEqual(p.docs_pairs, {
    "apps/api/src/**": "internal-docs/",
    "apps/nextjs/src/**": "internal-docs/frontend/",
  });
  assert.deepEqual(p.workspaces, {
    "apps/api": "@acme/api",
    "apps/nextjs": "@acme/nextjs",
  });
  assert.equal(p.lifecycle_suite, "pnpm --filter @acme/api test:e2e");
  // a multi-line flow map, with a trailing comma (prettier's output)
  const multi = parseMap(
    BASE.replace(
      '  workspaces: { "apps/api": "@acme/api", "apps/nextjs": "@acme/nextjs" }',
      '  workspaces:\n    {\n      "apps/api": "@acme/api",\n      "apps/nextjs": "@acme/nextjs",\n    }',
    ),
    "fixture.yml",
  );
  assert.deepEqual(multi.project.workspaces, p.workspaces);
  // an empty skills map: a project without review skills yet
  const empty = parseMap(
    BASE.replace(/skills:\n( {2}.*\n){3}/, "skills: {}\n").replace(
      /skills: \[[a-z-]+\]/g,
      "skills: []",
    ),
    "fixture.yml",
  );
  assert.deepEqual(empty.skills, {});
});

test("hard parse errors", () => {
  parseErr(
    BASE.replace('repo: "acme/app"', "repo: 'acme/app'"),
    /single-quoted/,
  );
  parseErr(
    BASE.replace('"architecture/billing.md"', '"architecture\\billing.md"'),
    /backslash/,
  );
  parseErr(
    BASE.replace('repo: "acme/app"', "repo: |\n    acme/app"),
    /block scalar/,
  );
  parseErr(
    BASE.replace('repo: "acme/app"', "repo: >\n    acme/app"),
    /block scalar/,
  );
  parseErr(
    BASE.replace('docs_only: ["', 'docs_only: &d ["'),
    /anchor or alias/,
  );
  parseErr(
    BASE.replace('lifecycle: ["apps/api/src/billing/**"]', "lifecycle: *d"),
    /anchor or alias/,
  );
  parseErr(
    BASE.replace("    skills: [billing-check]", "\tskills: [billing-check]"),
    /tab/,
  );
  parseErr(
    BASE.replace('when: "secrets in logs"', 'when: "secrets\tin logs"'),
    /tab/,
  );
  parseErr(BASE + "extra: 1\n", /unknown top-level key extra/);
  parseErr(
    BASE.replace(
      '    user_docs: ["billing/"]\n  - id: portal',
      '    user_docs: ["billing/"]\n    scope: ["x"]\n  - id: portal',
    ),
    /unknown rule key scope/,
  );
  parseErr(
    BASE.replace(
      '{ when: "an amount a user reads" }',
      '{ when: "an amount a user reads", scope: "x" }',
    ),
    /unknown key scope/,
  );
  parseErr(
    BASE.replace('paths: ["apps/api/src/**"]', "paths: [index.ts]"),
    /double-quoted strings/,
  );
  parseErr(
    BASE.replace(
      'paths: ["apps/api/src/**"]',
      "paths: [apps/api/src/index.ts]",
    ),
    /unexpected character "\/"/,
  );
  parseErr(
    BASE.replace("skills: [portal-review]", "skills: [nope]"),
    /unknown skill nope/,
  );
  parseErr(BASE.replace("    user_docs: []\n", ""), /missing user_docs/);
  parseErr(
    BASE.replace("- id: api-any", "- id: billing"),
    /duplicate rule id billing/,
  );
  parseErr(
    BASE.replace(', touch: "any file under apps/api/src/ (all of it)"', ""),
    /needs touch/,
  );
  parseErr(BASE.replace("version: 1", "version: 2"), /version must be 1/);
  parseErr(
    BASE.replace('user_docs: ["billing/"]', 'user_docs: ["billing"]'),
    /ending in \//,
  );
  parseErr(
    BASE.replace("  portal-review:", "   portal-review:"),
    /unexpected/,
  );
  parseErr(
    BASE.replace('repo: "acme/app"', 'repo: "acme/app'),
    /unterminated/,
  );
  parseErr(
    BASE.replace("  portal-review: { when:", "  portal-review: { when"),
    /expected key/,
  );
  parseErr(
    BASE + '  billing-check: { when: "again" }\n',
    /unexpected billing-check:/,
  );
  parseErr(BASE + '"stray"\n', /expected a top-level key/);
  parseErr(
    BASE.replace(
      "skills:\n  billing-check",
      'skills:\n  billing-check: { when: "x" }\n  billing-check',
    ),
    /duplicate skill/,
  );
  // a skill that no rule names and that carries no touch: prose is unreachable
  parseErr(
    BASE.replace("skills: [portal-review]", "skills: []"),
    /portal-review is named by no rule/,
  );
});

test("project: block errors", () => {
  parseErr(
    BASE.replace('  repo: "acme/app"\n', ""),
    /project: is missing repo/,
  );
  parseErr(BASE.replace('repo: "acme/app"', 'repo: "app"'), /owner\/name/);
  parseErr(
    BASE.replace('state_dir: "app-hooks"', 'state_dir: "a/b"'),
    /plain directory name/,
  );
  parseErr(
    BASE.replace("attribution_guard: true", 'attribution_guard: "yes"'),
    /true or false/,
  );
  parseErr(
    BASE.replace('  repo: "acme/app"', '  repo: "acme/app"\n  extra: "x"'),
    /unknown project key extra/,
  );
  parseErr(
    BASE.replace('{ "apps/api": "@acme/api",', '{ "apps/api" "@acme/api",'),
    /expected ':' after workspaces key "apps\/api"/,
  );
  parseErr(
    BASE.replace('{ "apps/api": "@acme/api",', '{ apps: "@acme/api",'),
    /workspaces keys must be double-quoted/,
  );
  parseErr(
    BASE.replace(
      '"apps/api": "@acme/api", "apps/nextjs"',
      '"apps/api": "@acme/api", "apps/api"',
    ),
    /duplicate workspaces key/,
  );
});

test("globs: bash globstar semantics", () => {
  assert.ok(globMatch("**/*.md", "CLAUDE.md"));
  assert.ok(globMatch("**/*.md", "apps/api/CLAUDE.md"));
  assert.ok(!globMatch("**/*.md", "apps/api/x.ts"));
  assert.ok(globMatch("**", "a/b/c"));
  assert.ok(globMatch("apps/*.ts", "apps/b.ts"));
  assert.ok(!globMatch("apps/*.ts", "apps/a/b.ts")); // * never crosses /
  assert.ok(globMatch("a?c", "abc"));
  assert.ok(!globMatch("a?c", "a/c")); // ? never crosses /
  assert.ok(!globMatch("a?c", "abbc"));
  assert.ok(
    globMatch(
      "apps/nextjs/src/app/(app)/billing/**",
      "apps/nextjs/src/app/(app)/billing/x.tsx",
    ),
  ); // parentheses literal
  assert.ok(
    !globMatch(
      "apps/nextjs/src/app/(app)/billing/**",
      "apps/nextjs/src/app/app/billing/x.tsx",
    ),
  );
  assert.ok(globMatch("dir/**", "dir/a/b/c"));
  assert.ok(!globMatch("dir/**", "dirx/a"));
  assert.ok(globMatch("a/**/b", "a/b")); // ** = zero segments
  assert.ok(globMatch("a/**/b", "a/x/y/b"));
  assert.ok(
    globMatch(
      "apps/api/src/**/schemas/*.schema.ts",
      "apps/api/src/users/schemas/user.schema.ts",
    ),
  );
  assert.ok(
    !globMatch(
      "apps/api/src/**/schemas/*.schema.ts",
      "apps/api/src/users/schemas/sub/user.schema.ts",
    ),
  );
  assert.ok(!globMatch("*.ts", "xts")); // dot is literal
  assert.ok(
    globMatch(
      "apps/nextjs/src/app/(app)/users/*/_components/Batch*.tsx",
      "apps/nextjs/src/app/(app)/users/[id]/_components/BatchTable.tsx",
    ),
  );
  assert.ok(
    !globMatch(
      "apps/api/src/users/enrollment-*.ts",
      "apps/api/src/users/enrollment-writes.spec.tsx",
    ),
  );
  assert.ok(globMatch("**/*NavBadge*", ".hidden/x/NavBadge.tsx")); // dotfiles are not special
});

test("match: union per path, verdicts, docs area, required_skills excludes trigger_only", () => {
  const m = parseMap(BASE, "fixture.yml");
  const out = matchPaths(m, [
    "apps/api/src/math/rates-eu.ts",
    "./internal-docs/x.md",
    ".claude/x.md",
    "apps/nextjs/messages/en.json",
    "apps/nextjs/src/app/(app)/billing/page.tsx",
    "apps/api/src/billing/x.spec.ts",
  ]);
  const w = out.paths["apps/api/src/math/rates-eu.ts"];
  assert.deepEqual(w.rules, ["billing", "api-any"]);
  assert.deepEqual(w.skills, ["billing-check", "security-check"]);
  assert.deepEqual(w.internal_docs, ["architecture/billing.md"]);
  assert.deepEqual(w.user_docs, ["billing/"]);
  assert.equal(w.lifecycle, false);
  assert.equal(w.docs_area, "internal-docs/");
  assert.equal(w.user_visible, false);
  assert.equal(w.docs_only, "never");
  const page = out.paths["apps/nextjs/src/app/(app)/billing/page.tsx"];
  assert.equal(page.docs_area, "internal-docs/frontend/");
  assert.equal(page.user_visible, true);
  const spec = out.paths["apps/api/src/billing/x.spec.ts"];
  assert.equal(spec.docs_area, null, "docs_exempt: a spec needs no docs");
  assert.equal(spec.lifecycle, true);
  assert.equal(out.paths["internal-docs/x.md"].docs_only, "docs"); // leading ./ stripped
  assert.equal(out.paths["internal-docs/x.md"].docs_area, null);
  assert.equal(out.paths[".claude/x.md"].docs_only, "never"); // never wins over **/*.md
  assert.equal(out.paths["apps/nextjs/messages/en.json"].docs_only, "code");
  assert.deepEqual(out.paths["apps/nextjs/messages/en.json"].rules, []);
  assert.deepEqual(out.required_skills, ["billing-check", "portal-review"]); // sorted, no security-check
  assert.deepEqual(Object.keys(out.skills).sort(), [
    "billing-check",
    "portal-review",
    "security-check",
  ]);
  assert.equal(out.skills["security-check"].trigger_only, true);
  assert.equal(docsOnlyVerdict(m, "DESIGN.md"), "docs");
  assert.deepEqual(matchPaths(m, []), {
    paths: {},
    skills: {},
    required_skills: [],
  });
});

test("config: the project block as shell assignments", () => {
  const out = shellConfig(parseMap(BASE, "fixture.yml"));
  assert.ok(out.includes("HOOK_CFG_REPO='acme/app'\n"));
  assert.ok(out.includes("HOOK_CFG_ATTRIBUTION_GUARD='yes'\n"));
  assert.ok(
    out.includes(
      "HOOK_CFG_WORKSPACES='apps/api\t@acme/api\napps/nextjs\t@acme/nextjs'\n",
    ),
  );
  assert.ok(
    out.includes(
      "HOOK_CFG_DEPS_CHECK='pnpm install --frozen-lockfile --lockfile-only --offline\npnpm typecheck'\n",
    ),
  );
  // a single quote survives the shell round trip
  assert.ok(out.includes("HOOK_CFG_SECRET_EXEMPT='*.md\nit'\\''s*'\n"));
  const r = spawnSync(
    "bash",
    ["-c", `${out}\nprintf '%s' "$HOOK_CFG_SECRET_EXEMPT"`],
    { encoding: "utf8" },
  );
  assert.equal(r.stdout, "*.md\nit's*");
});

test("render: touch prose for trigger-only rows, joined paths otherwise", () => {
  const m = parseMap(BASE, "fixture.yml");
  assert.deepEqual(skillPaths(m, "billing-check"), [
    "apps/api/src/billing/**",
    "apps/api/src/math/rates*.ts",
  ]);
  const skills = renderSkillsTable(m);
  assert.match(
    skills,
    /^\| Skill \| Touch \| When \|\n\| --- \| --- \| --- \|\n/,
  );
  assert.ok(
    skills.includes(
      "| `/billing-check` | `apps/api/src/billing/**`, `apps/api/src/math/rates*.ts` | rates, totals, rounding |",
    ),
  );
  assert.ok(
    skills.includes(
      "| `/security-check` | any file under apps/api/src/ (all of it) | secrets in logs |",
    ),
  );
  const api = renderApiPagesTable(m);
  assert.match(
    api,
    /^\| You're touching… \| Read \/ update \|\n\| --- \| --- \|\n/,
  );
  assert.ok(
    api.includes(
      "| `billing/**`, `math/rates*.ts` | `architecture/billing.md` |",
    ),
  );
  assert.ok(!api.includes("portal"), "portal rules have no apps/api path");
  assert.ok(!api.includes("apps/api/src/**"), "api-any has no page");
  const doc =
    "intro\n\n<!-- review-map:skills -->\nstale\n<!-- /review-map:skills -->\n\nouter\n";
  const out = renderBlocks(m, doc, "x.md");
  assert.ok(out.startsWith("intro\n\n<!-- review-map:skills -->\n\n| Skill |"));
  assert.ok(out.endsWith("|\n\n<!-- /review-map:skills -->\n\nouter\n"));
  assert.throws(
    () => renderBlocks(m, "no markers", "x.md"),
    /no <!-- review-map/,
  );
  assert.throws(
    () =>
      renderBlocks(
        m,
        "<!-- review-map:nope -->\n<!-- /review-map:nope -->",
        "x.md",
      ),
    /unknown block/,
  );
});

test("checkMap: errors, warnings and info with an injected tree", () => {
  const m = parseMap(BASE, "fixture.yml");
  const files = [
    "CLAUDE.md",
    "apps/docs/en/billing/overview.md",
    "apps/api/package.json",
    "apps/api/src/math/rates.ts",
    "apps/api/src/billing/x.ts",
    "apps/nextjs/package.json",
    "apps/nextjs/src/app/(app)/billing/page.tsx",
    ".claude/review-map.yml",
    "internal-docs/.vitepress/config.mts",
  ];
  const io = (over = {}) => ({
    files,
    fileExists: (p) =>
      [
        "internal-docs/architecture/billing.md",
        "internal-docs/frontend/README.md # not a comment",
        "apps/api/package.json",
        "apps/nextjs/package.json",
      ].includes(p),
    dirExists: (p) =>
      [
        "apps/docs/en/billing/",
        "internal-docs",
        "internal-docs/frontend",
      ].includes(p),
    render: () => ({ currentBlocks: "same", freshBlocks: "same" }),
    ...over,
  });
  const clean = checkMap(m, io());
  assert.deepEqual(clean.errors, []);
  assert.deepEqual(clean.warnings, []);
  assert.deepEqual(clean.infos, [], "no overlap in the fixture tree");

  const stale = checkMap(
    m,
    io({ render: () => ({ currentBlocks: "old", freshBlocks: "new" }) }),
  );
  assert.equal(stale.errors.length, 1, "one rendered file in the fixture");
  assert.match(
    stale.errors[0],
    /CLAUDE\.md: the review-map block is stale; run: node scripts\/review-map\.mjs render CLAUDE\.md/,
  );

  const noPage = checkMap(
    m,
    io({ fileExists: () => false, dirExists: () => false }),
  );
  for (const want of [
    'rule billing: internal_docs "architecture/billing.md" is not a file under internal-docs/',
    'rule billing: user_docs "billing/" is not a directory under apps/docs/en/',
    'project.docs_pairs: "internal-docs/frontend/" is not a directory',
    'project.workspaces: "apps/api" has no package.json',
  ])
    assert.ok(noPage.errors.includes(want), `missing: ${want}`);

  const noUserDocs = checkMap(
    parseMap(
      BASE.replace('user_docs_root: "apps/docs/en"', 'user_docs_root: ""'),
      "fixture.yml",
    ),
    io(),
  );
  assert.ok(
    noUserDocs.errors.includes(
      'rule billing: user_docs "billing/" given but project.user_docs_root is empty',
    ),
  );

  const noFile = checkMap(
    m,
    io({ files: files.filter((f) => !f.startsWith("apps/api/src/")) }),
  );
  for (const want of [
    'lifecycle: "apps/api/src/billing/**" matches no tracked file',
    'rule billing: paths "apps/api/src/math/rates*.ts" matches no tracked file',
    'project.docs_pairs: "apps/api/src/**" matches no tracked file',
  ])
    assert.ok(noFile.errors.includes(want), `missing: ${want}`);

  const m2 = parseMap(
    BASE.replace(
      'docs_only: ["**/*.md", "apps/docs/en/**/*.md"]',
      'docs_only: ["**/*.md", "internal-docs/.vitepress/**"]',
    ),
    "fixture.yml",
  );
  const odd = checkMap(m2, io());
  assert.deepEqual(odd.errors, []);
  assert.ok(
    odd.warnings.some((w) =>
      w.startsWith(
        'docs_only "internal-docs/.vitepress/**" matches 1 non-md/png/gitkeep file(s), e.g. internal-docs/.vitepress/config.mts',
      ),
    ),
  );

  const m3 = parseMap(
    BASE.replace(
      'never_docs_only: [".claude/**", "**/*.ts"]',
      'never_docs_only: [".claude/**", "**/*.ts", "CLAUDE.md"]',
    ),
    "fixture.yml",
  );
  assert.ok(
    checkMap(m3, io()).infos.some((i) =>
      i.startsWith(
        'docs_only "**/*.md" and never_docs_only "CLAUDE.md" overlap on 1 file(s), e.g. CLAUDE.md; never_docs_only wins',
      ),
    ),
  );
});

test("the committed map loads and its skills are reachable", () => {
  const m = loadMap(SCRIPT_TOP);
  assert.equal(m.version, 1);
  for (const [name, s] of Object.entries(m.skills)) {
    if (s.trigger_only) assert.ok(s.touch, `${name} carries touch: prose`);
    else
      assert.ok(skillPaths(m, name).length > 0, `${name} is named by a rule`);
  }
  const auth = matchPaths(m, ["apps/api/src/auth/auth.service.ts"]).paths[
    "apps/api/src/auth/auth.service.ts"
  ];
  assert.equal(auth.docs_area, "internal-docs/");
  assert.deepEqual(auth.internal_docs, ["architecture/auth.md"]);
  assert.equal(auth.lifecycle, true);
  for (const [dir, pkg] of Object.entries(m.project.workspaces))
    assert.match(pkg, /^@[a-z0-9-]+\//, `${dir} names a scoped package`);
});

test("cli: lists, config and match print, a bad subcommand exits 1", () => {
  const run = (...args) =>
    spawnSync(process.execPath, ["scripts/review-map.mjs", ...args], {
      cwd: SCRIPT_TOP,
      encoding: "utf8",
    });
  const lists = run("lists");
  assert.equal(lists.status, 0, lists.stderr);
  assert.equal(JSON.parse(lists.stdout).version, 1);
  const config = run("config");
  assert.equal(config.status, 0, config.stderr);
  assert.match(config.stdout, /^HOOK_CFG_REPO='[^']+\/[^']+'$/m);
  const match = run("match", "apps/api/src/auth/auth.service.ts");
  assert.equal(match.status, 0, match.stderr);
  assert.ok(
    JSON.parse(match.stdout).skills.cso,
    "the auth path names the trigger-only cso skill",
  );
  const bad = run("bogus");
  assert.equal(bad.status, 1);
  assert.match(bad.stderr, /^review-map: usage:/);
});

// Regression: `match` over a large branch produces well over 64 KB of JSON.
// With process.exit() the process died before a PIPED stdout drained, the
// consumer (ai-review.sh | jq) got a truncated document and required only
// `review`. The whole document must arrive through a pipe.
test("match writes its whole answer through a pipe, past 64 KB", () => {
  const paths = Array.from(
    { length: 600 },
    (_, i) => `apps/api/src/auth/generated-path-${i}.service.ts`,
  );
  const r = spawnSync(
    process.execPath,
    [new URL("./review-map.mjs", import.meta.url).pathname, "match", ...paths],
    { encoding: "utf8", maxBuffer: 64 * 1024 * 1024 },
  );
  assert.equal(r.status, 0, r.stderr);
  assert.ok(r.stdout.length > 64 * 1024, `only ${r.stdout.length} bytes`);
  const parsed = JSON.parse(r.stdout);
  assert.equal(Object.keys(parsed.paths).length, paths.length);
  assert.ok(
    Object.values(parsed.paths).every((p) => p.docs_area === "internal-docs/"),
  );
});
