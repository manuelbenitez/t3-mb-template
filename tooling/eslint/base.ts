import compat from "@eslint/compat";
import js from "@eslint/js";
import importPlugin from "eslint-plugin-import";
import react from "eslint-plugin-react";
import reactHooks from "eslint-plugin-react-hooks";
import tseslint from "typescript-eslint";

export default tseslint.config(
  { ignores: ["*.config.js", "*.config.ts"] },
  js.configs.recommended,
  ...tseslint.configs.recommended,
  ...compat.configs.recommended,
  {
    plugins: {
      react: react,
      "react-hooks": reactHooks,
      import: importPlugin,
    },
    rules: {
      ...react.configs.recommended.rules,
      ...reactHooks.configs.recommended.rules,
      "import/no-duplicates": "error",
      "import/order": [
        "error",
        {
          groups: [
            "builtin",
            "external",
            "parent",
            "sibling",
            "index",
            "object",
            "type",
          ],
          pathGroups: [
            { pattern: "@acme/**", group: "parent", position: "before" },
            { pattern: "~/**", group: "sibling", position: "after" },
          ],
          pathGroupsExcludedImportPatterns: ["^@acme"],
        },
      ],
      "react/jsx-sort-props": "error",
      "react/self-closing-comp": "error",
    },
  },
);