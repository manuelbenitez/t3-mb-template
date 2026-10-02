import { fixupPluginRules } from "@eslint/compat";
import importPlugin from "eslint-plugin-import";
import react from "eslint-plugin-react";
import reactHooks from "eslint-plugin-react-hooks";
import tseslint from "typescript-eslint";
import js from "@eslint/js";

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
);
