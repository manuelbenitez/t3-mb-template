import { fileURLToPath } from "node:url";
import { defineConfig } from "vitest/config";

export default defineConfig({
  resolve: {
    // Mirror every alias tsconfig.json declares.
    alias: { "~": fileURLToPath(new URL("./src", import.meta.url)) },
  },
  // tsconfig has jsx: "preserve" for Next; vitest needs a real transform.
  esbuild: { jsx: "automatic" },
  test: {
    include: [
      "src/**/*.test.ts",
      "src/**/*.test.tsx",
      "src/**/*.spec.ts",
      "src/**/*.spec.tsx",
    ],
    exclude: ["node_modules", ".next"],
    // Node by default; a component test opts in with a
    // `// @vitest-environment jsdom` docblock.
  },
});
