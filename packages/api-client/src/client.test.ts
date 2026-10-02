import { afterEach, describe, expect, it, vi } from "vitest";
import { ApiClient, ApiError } from "./client";

function mockFetch(response: Response) {
  const fn = vi.fn().mockResolvedValue(response);
  vi.stubGlobal("fetch", fn);
  return fn;
}

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("ApiClient", () => {
  it("sends the bearer token and parses JSON", async () => {
    const fetchFn = mockFetch(
      new Response(JSON.stringify({ ok: true }), { status: 200 }),
    );
    const client = new ApiClient({
      baseUrl: "http://api.test",
      getToken: () => "tok",
    });

    await expect(client.get("/api/x", { params: { a: "1" } })).resolves.toEqual(
      { ok: true },
    );
    const [url, init] = fetchFn.mock.calls[0] as [string, RequestInit];
    expect(url).toBe("http://api.test/api/x?a=1");
    expect((init.headers as Record<string, string>).Authorization).toBe(
      "Bearer tok",
    );
  });

  it("returns undefined on 204", async () => {
    mockFetch(new Response(null, { status: 204 }));
    const client = new ApiClient({ baseUrl: "http://api.test" });
    await expect(client.delete("/api/x")).resolves.toBeUndefined();
  });

  it("throws ApiError with the response body", async () => {
    mockFetch(
      new Response(JSON.stringify({ message: "nope" }), {
        status: 403,
        statusText: "Forbidden",
      }),
    );
    const client = new ApiClient({ baseUrl: "http://api.test" });
    const err = await client.get("/api/x").catch((e: unknown) => e);
    expect(err).toBeInstanceOf(ApiError);
    expect((err as ApiError).status).toBe(403);
    expect((err as ApiError).data).toEqual({ message: "nope" });
  });
});
