import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { ESLint } from "eslint";
import config from "./base.ts";

const eslint = new ESLint({
  cwd: import.meta.dirname,
  overrideConfigFile: true,
  overrideConfig: config,
  fix: true,
});

async function lint(filePath: string, code: string) {
  const [result] = await eslint.lintText(code, { filePath });
  const jsdoc = result.messages.filter((m) => m.ruleId?.startsWith("jsdoc/"));
  return { jsdoc, output: result.output ?? code };
}

describe("jsdoc rules", () => {
  it("require JSDoc on every module-level declaration, not on locals or constructors", async () => {
    const { jsdoc } = await lint(
      "src/shapes.ts",
      [
        "export function exported() {",
        "  function nested() {}",
        "  return nested;",
        "}",
        "const local = 1;",
        "export class Service {",
        "  constructor() {}",
        "  run() {}",
        "  handler = () => 1;",
        "}",
        "export interface Shape { a: string }",
        "export type Alias = string;",
        "export enum Kind { A }",
        "export default () => local;",
        "export const exportedConst = 1;",
        "export abstract class Base {",
        "  abstract go(): void;",
        "}",
        "",
      ].join("\n"),
    );
    const lines = jsdoc
      .filter((m) => m.ruleId === "jsdoc/require-jsdoc")
      .map((m) => m.line);
    assert.deepEqual(lines, [1, 5, 6, 8, 9, 11, 12, 13, 14, 15, 16, 17]);
  });

  it("accept a complete block", async () => {
    const { jsdoc } = await lint(
      "src/login.ts",
      [
        "/**",
        " * Checks the password.",
        " *",
        " * @param password - The password.",
        " * @returns Whether it matches.",
        " * @throws {Error} When the password is empty.",
        " */",
        "export function check(password: string) {",
        '  if (!password) throw new Error("empty");',
        '  return password === "x";',
        "}",
        "",
      ].join("\n"),
    );
    assert.deepEqual(jsdoc, []);
  });

  it("never delete text on --fix", async () => {
    const { output } = await lint(
      "src/keep.ts",
      [
        "/**",
        " * Keeps a value.",
        " *",
        " * Steps:",
        " * * parse the token",
        " * * check the role",
        " *",
        " * @internal Kept for the migration.",
        " * @abstract",
        " * @typeParam T - The value type.",
        " * @param value - The value.",
        " * @param [count=1] - How many.",
        " * @returns The value.",
        " */",
        "export function keep<T>(value: T, count = 1): T {",
        "  return count ? value : value;",
        "}",
        "",
      ].join("\n"),
    );
    assert.match(output, /@internal Kept for the migration\./);
    // An alias tag is renamed to its canonical name (`@typeParam` to
    // `@template`); its text must survive.
    assert.match(output, / T - The value type\./);
    assert.match(output, /\[count=1\]/);
    assert.match(output, / \* \* parse the token\n \* \* check the role/);
    assert.match(output, /@abstract/);
  });

  it("never insert placeholder tags on --fix", async () => {
    const code = [
      "/** Echoes the value. */",
      "export function echo(value: string): string {",
      "  return value;",
      "}",
      "",
    ].join("\n");
    const { output } = await lint("src/echo.ts", code);
    assert.equal(output, code);
  });

  it("resolve a jsdoc/* directive in plain JavaScript", async () => {
    const [result] = await eslint.lintText(
      "// eslint-disable-next-line jsdoc/require-jsdoc -- generated\nexport const a = 1;\n",
      { filePath: "src/gen.mjs" },
    );
    assert.deepEqual(
      result.messages.filter((m) => m.severity === 2),
      [],
    );
  });

  for (const file of ["src/a.ts", "src/config/jwt.config.ts"]) {
    it(`require JSDoc in ${file}`, async () => {
      const { jsdoc } = await lint(file, "export const a = 1;\n");
      assert.deepEqual(
        jsdoc.map((m) => m.ruleId),
        ["jsdoc/require-jsdoc"],
      );
    });
  }

  it("leave plain JavaScript and its {types} alone", async () => {
    const { jsdoc, output } = await lint(
      "scripts/check.mjs",
      [
        "/**",
        " * @param {number} a",
        " * @returns {number}",
        " */",
        "export function f(a) {",
        "  return a;",
        "}",
        "export const g = 1;",
        "",
      ].join("\n"),
    );
    assert.deepEqual(jsdoc, []);
    assert.match(output, /@param \{number\} a/);
  });

  it("accept a test-environment docblock", async () => {
    const { jsdoc } = await lint(
      "src/widget.ts",
      '/** @vitest-environment jsdom */\nimport "./setup";\n',
    );
    assert.deepEqual(jsdoc, []);
  });

  for (const file of [
    "src/a.spec.ts",
    "src/a.spec.tsx",
    "src/a.e2e-spec.ts",
    "src/a.test.ts",
    "src/a.test.tsx",
    "src/a.stories.tsx",
    "vite.config.mts",
    "src/testing/a.ts",
  ]) {
    it(`exempt ${file}`, async () => {
      const { jsdoc } = await lint(file, "export const a = 1;\n");
      assert.deepEqual(jsdoc, []);
    });
  }
});
