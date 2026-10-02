import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    // Both conventions: apps/api uses *.spec.ts, everything else *.test.ts.
    include: ["src/**/*.test.ts", "src/**/*.spec.ts"],
    exclude: ["node_modules", "dist"],
  },
});
