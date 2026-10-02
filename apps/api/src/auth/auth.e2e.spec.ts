import type { Model } from "mongoose";
import request from "supertest";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { getModelToken } from "@nestjs/mongoose";
import type { TestApp } from "../testing/test-app";
import { createTestApp } from "../testing/test-app";
import type { UserDocument } from "../users/schemas/user.schema";
import { User } from "../users/schemas/user.schema";

describe("auth (e2e)", () => {
  let t: TestApp;
  let users: Model<UserDocument>;
  const http = () => request(t.app.getHttpServer());

  beforeAll(async () => {
    t = await createTestApp();
    users = t.app.get(getModelToken(User.name));
  });

  afterAll(async () => {
    await t.close();
  });

  async function register(email: string) {
    const res = await http()
      .post("/api/auth/register")
      .send({ name: "Test User", email, password: "correct-horse" })
      .expect(201);
    return res.body.access_token as string;
  }

  it("registers, logs in and reads the session", async () => {
    const reg = await http()
      .post("/api/auth/register")
      .send({
        name: "Ada Lovelace",
        email: "ada@example.com",
        password: "correct-horse",
      })
      .expect(201);
    expect(reg.body.user.roles).toEqual(["user"]);
    expect(reg.body.user.password).toBeUndefined();

    const login = await http()
      .post("/api/auth/login")
      .send({ email: "ada@example.com", password: "correct-horse" })
      .expect(201);

    const session = await http()
      .get("/api/auth/session")
      .set("Authorization", `Bearer ${login.body.access_token}`)
      .expect(200);
    expect(session.body.user.email).toBe("ada@example.com");
    expect(session.body.user.password).toBeUndefined();
  });

  it("rejects a wrong password", async () => {
    await http()
      .post("/api/auth/login")
      .send({ email: "ada@example.com", password: "wrong-password" })
      .expect(401);
  });

  it("refuses a role sent on register", async () => {
    await http()
      .post("/api/auth/register")
      .send({
        name: "Mallory",
        email: "mallory@example.com",
        password: "correct-horse",
        roles: ["admin"],
      })
      .expect(400);
  });

  it("guards every route by default", async () => {
    await http().get("/api/auth/session").expect(401);
    await http().get("/api/users/me").expect(401);
    await http()
      .get("/api/users/me")
      .set("Authorization", "Bearer not-a-token")
      .expect(401);
  });

  it("keeps the user list admin-only", async () => {
    const token = await register("member@example.com");
    await http()
      .get("/api/users")
      .set("Authorization", `Bearer ${token}`)
      .expect(403);

    await users.updateOne(
      { email: "member@example.com" },
      { roles: ["user", "admin"] },
    );
    const list = await http()
      .get("/api/users")
      .set("Authorization", `Bearer ${token}`)
      .expect(200);
    expect(list.body.length).toBeGreaterThan(0);
    expect(list.body[0].password).toBeUndefined();
  });

  it("forbids a suspended account even with a valid token", async () => {
    const token = await register("suspended@example.com");
    await users.updateOne(
      { email: "suspended@example.com" },
      { accountStatus: "suspended" },
    );
    await http()
      .get("/api/users/me")
      .set("Authorization", `Bearer ${token}`)
      .expect(403);
  });
});
