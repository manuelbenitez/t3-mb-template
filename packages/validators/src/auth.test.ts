import { describe, expect, it } from "vitest";
import { loginSchema, registerSchema } from "./auth";

describe("loginSchema", () => {
  it("accepts a valid login", () => {
    expect(
      loginSchema.safeParse({ email: "a@example.com", password: "x" }).success,
    ).toBe(true);
  });

  it("rejects a malformed email", () => {
    expect(
      loginSchema.safeParse({ email: "nope", password: "x" }).success,
    ).toBe(false);
  });
});

describe("registerSchema", () => {
  it("rejects a short password", () => {
    const r = registerSchema.safeParse({
      name: "A",
      email: "a@example.com",
      password: "12345",
    });
    expect(r.success).toBe(false);
  });
});
