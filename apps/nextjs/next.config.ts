import { createJiti } from "jiti";
import type { NextConfig } from "next";

const jiti = createJiti(import.meta.url);

// Validate env at build time
await jiti.import("./src/env");

const config: NextConfig = {
  transpilePackages: ["@acme/api-client", "@acme/ui", "@acme/validators"],
  typescript: { ignoreBuildErrors: true },
};

export default config;
