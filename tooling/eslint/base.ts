import importPlugin from "eslint-plugin-import";
import jsdoc from "eslint-plugin-jsdoc";
import react from "eslint-plugin-react";
import reactHooks from "eslint-plugin-react-hooks";
import tseslint from "typescript-eslint";
import { fixupPluginRules } from "@eslint/compat";
import js from "@eslint/js";

/** The files the JSDoc rules apply to: they assume types live in TypeScript. */
const typescript = ["**/*.ts", "**/*.tsx", "**/*.mts", "**/*.cts"];

/**
 * Selectors for a declaration at the top of a module, bare or exported.
 *
 * @param node - The AST node type.
 * @returns One selector per form.
 */
const moduleLevel = (node: string) => [
  `Program > ${node}`,
  `Program > ExportNamedDeclaration > ${node}`,
  `Program > ExportDefaultDeclaration > ${node}`,
];

export default tseslint.config(
  {
    ignores: [
      "*.config.js",
      "*.config.ts",
      "dist/**",
      "node_modules/**",
      ".next/**",
      "coverage/**",
    ],
  },
  js.configs.recommended,
  ...tseslint.configs.recommended,
  {
    // react and import predate ESLint 10's context API; the compat shim
    // restores it. Drop the wrapper once they declare eslint ^10.
    plugins: {
      react: fixupPluginRules(react),
      "react-hooks": reactHooks,
      import: fixupPluginRules(importPlugin),
    },
    settings: {
      react: { version: "detect" },
    },
    rules: {
      ...react.configs.recommended.rules,
      ...reactHooks.configs.recommended.rules,
      "react/react-in-jsx-scope": "off",
      "import/no-duplicates": "error",
      "react/self-closing-comp": "error",
    },
  },
  // The convention: internal-docs/conventions/code-style.md. Fixers that would
  // insert placeholder docs or delete text stay off: the on-edit hook runs
  // --fix unseen. TypeScript files only, since the rules assume no `{types}`.
  // The plugin is registered for every file, so a jsdoc/* directive in a .js
  // file still resolves; only the rules are TypeScript-only.
  { plugins: { jsdoc } },
  {
    files: typescript,
    rules: {
      ...jsdoc.configs["flat/recommended-typescript-error"].rules,
      "jsdoc/require-jsdoc": [
        "error",
        {
          publicOnly: false,
          require: { FunctionDeclaration: false },
          enableFixer: false,
          contexts: [
            ...moduleLevel("FunctionDeclaration"),
            // The plugin does not look past `export` for a variable, so the
            // exported form is matched on the export node itself.
            "Program > VariableDeclaration",
            'Program > ExportNamedDeclaration[declaration.type="VariableDeclaration"]',
            ...moduleLevel("ClassDeclaration"),
            ...moduleLevel("TSInterfaceDeclaration"),
            ...moduleLevel("TSTypeAliasDeclaration"),
            ...moduleLevel("TSEnumDeclaration"),
            "Program > ExportDefaultDeclaration > ArrowFunctionExpression",
            'MethodDefinition:not([kind="constructor"])',
            "TSAbstractMethodDefinition",
            'PropertyDefinition[value.type="ArrowFunctionExpression"]',
          ],
        },
      ],
      "jsdoc/require-description": [
        "error",
        {
          contexts: ["any"],
          exemptedBy: ["inheritdoc", "vitest-environment", "jest-environment"],
        },
      ],
      "jsdoc/check-tag-names": [
        "error",
        {
          typed: true,
          enableFixer: false,
          definedTags: ["vitest-environment", "jest-environment"],
        },
      ],
      "jsdoc/empty-tags": "off",
      "jsdoc/no-defaults": "off",
      "jsdoc/no-multi-asterisks": ["error", { allowWhitespace: true }],
      "jsdoc/require-param": [
        "error",
        {
          enableFixer: false,
          checkDestructured: false,
          unnamedRootBase: ["props", "arg"],
        },
      ],
      "jsdoc/check-param-names": ["error", { checkDestructured: false }],
      "jsdoc/require-returns": ["error", { enableFixer: false }],
      "jsdoc/require-throws": "error",
      "jsdoc/require-throws-description": "error",
      "jsdoc/require-hyphen-before-param-description": "error",
      "jsdoc/no-blank-blocks": "error",
      "jsdoc/tag-lines": ["error", "any", { startLines: 1 }],
    },
  },
  {
    files: [
      "**/*.spec.{ts,tsx}",
      "**/*.e2e-spec.ts",
      "**/*.test.{ts,tsx}",
      "**/*.stories.tsx",
      "*.config.{mts,cts}",
      "**/testing/**",
    ],
    rules: {
      "jsdoc/require-jsdoc": "off",
    },
  },
);
