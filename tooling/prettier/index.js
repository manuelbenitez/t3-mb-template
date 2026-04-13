/** @type {import('prettier').Config} */
export default {
  plugins: [
    "@ianvs/prettier-plugin-sort-imports",
    "prettier-plugin-tailwindcss",
  ],
  importOrder: [
    "^(react/(.*)$)|^(react$)",
    "^(next/(.*)$)|^(next$)",
    "^(next-intl/(.*)$)",
    "^(@acme/(.*)$)",
    "^(@(?!acme/)(.*)/([^/]+)$)",
    "^~/",
    "^[../]",
    "^[.]",
  ],
};