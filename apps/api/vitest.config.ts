import swc from "unplugin-swc";
import { defineConfig } from "vitest/config";

export default defineConfig({
  // esbuild drops decorator metadata, which Nest's DI needs; SWC keeps it.
  plugins: [swc.vite({ module: { type: "es6" } })],
  test: {
    globals: true,
    include: ["src/**/*.spec.ts"],
    root: "./",
    // Each e2e spec boots its own mongodb-memory-server.
    maxWorkers: 2,
    testTimeout: 30_000,
    hookTimeout: 60_000,
  },
});
