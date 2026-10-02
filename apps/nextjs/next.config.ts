import type { NextConfig } from "next";
// Validate env at build time
import "./src/env";

const config: NextConfig = {
  transpilePackages: ["@acme/api-client", "@acme/ui", "@acme/validators"],
  typescript: { ignoreBuildErrors: true },
};

export default config;
