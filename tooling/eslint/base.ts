import importPlugin from "eslint-plugin-import";
import jsdoc from "eslint-plugin-jsdoc";
import react from "eslint-plugin-react";
import reactHooks from "eslint-plugin-react-hooks";
import tseslint from "typescript-eslint";
import { fixupPluginRules } from "@eslint/compat";
import js from "@eslint/js";

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
  // insert placeholder docs stay off, so --fix never writes an empty block.
  jsdoc.configs["flat/recommended-typescript-error"],
  {
    rules: {
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
            'MethodDefinition:not([kind="constructor"])',
          ],
        },
      ],
      "jsdoc/require-description": ["error", { contexts: ["any"] }],
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
      "**/*.spec.ts",
      "**/*.test.ts",
      "**/*.test.tsx",
      "**/*.stories.tsx",
      "**/testing/**",
    ],
    rules: {
      "jsdoc/require-jsdoc": "off",
    },
  },
);
