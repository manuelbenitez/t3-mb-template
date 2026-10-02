import { describe, expect, it } from "vitest";
import { validateEnv } from "./env.validation";

const good = {
  MONGODB_URI: "mongodb://localhost:27017/app",
  JWT_SECRET: "x".repeat(32),
};

describe("validateEnv", () => {
  it("accepts a valid environment", () => {
    expect(validateEnv(good)).toMatchObject(good);
  });

  it("rejects a missing JWT_SECRET", () => {
    expect(() => validateEnv({ ...good, JWT_SECRET: undefined })).toThrow(
      /JWT_SECRET/,
    );
  });

  it("rejects a JWT_SECRET under 32 characters", () => {
    expect(() => validateEnv({ ...good, JWT_SECRET: "x".repeat(31) })).toThrow(
      /JWT_SECRET/,
    );
  });

  it("rejects the .env.example placeholder", () => {
    expect(() =>
      validateEnv({
        ...good,
        JWT_SECRET: "change-me-use-openssl-rand-base64-32",
      }),
    ).toThrow(/JWT_SECRET/);
  });

  it("rejects a non-mongodb URI", () => {
    expect(() => validateEnv({ ...good, MONGODB_URI: "postgres://x" })).toThrow(
      /MONGODB_URI/,
    );
  });
});
