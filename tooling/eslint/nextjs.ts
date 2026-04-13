import type { Linter } from "eslint";
import nextPlugin from "@next/eslint-plugin-next";
import baseConfig from "./base.js";

const config: Linter.Config[] = [
  ...baseConfig,
  {
    plugins: {
      "@next/next": nextPlugin,
    },
    rules: {
      ...nextPlugin.configs.recommended.rules,
      "@next/next/no-html-link-for-pages": "warn",
      "@next/next/no-img-element": "warn",
    },
  },
];

export default config;
