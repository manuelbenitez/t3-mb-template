import request from "supertest";
import type { TestApp } from "../testing/test-app";
import { createTestApp } from "../testing/test-app";

describe("auth (e2e)", () => {
  let t: TestApp;

  beforeAll(async () => {
    t = await createTestApp();
  });

  afterAll(async () => {
    await t.close();
  });

  const user = {
    name: "Ada Lovelace",
    email: "ada@example.com",
    password: "correct-horse",
  };

  it("registers, logs in and reads the session", async () => {
    const reg = await request(t.app.getHttpServer())
      .post("/api/auth/register")
      .send(user)
      .expect(201);
    expect(reg.body.access_token).toEqual(expect.any(String));
    expect(reg.body.user.email).toBe(user.email);
    expect(reg.body.user.password).toBeUndefined();

    const login = await request(t.app.getHttpServer())
      .post("/api/auth/login")
      .send({ email: user.email, password: user.password })
      .expect(201);

    const session = await request(t.app.getHttpServer())
      .get("/api/auth/session")
      .set("Authorization", `Bearer ${login.body.access_token}`)
      .expect(200);
    expect(session.body.user.email).toBe(user.email);
    expect(session.body.user.password).toBeUndefined();
  });

  it("rejects a wrong password", async () => {
    await request(t.app.getHttpServer())
      .post("/api/auth/login")
      .send({ email: user.email, password: "wrong-password" })
      .expect(401);
  });

  it("rejects a session request without a token", async () => {
    await request(t.app.getHttpServer()).get("/api/auth/session").expect(401);
  });
});
