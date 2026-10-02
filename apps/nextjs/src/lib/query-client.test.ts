import { describe, expect, it } from "vitest";
import { getQueryClient, makeQueryClient } from "./query-client";

describe("query client", () => {
  it("applies the default query options", () => {
    const opts = makeQueryClient().getDefaultOptions().queries;
    expect(opts?.staleTime).toBe(60_000);
    expect(opts?.retry).toBe(1);
  });

  it("returns a fresh client per call on the server", () => {
    expect(getQueryClient()).not.toBe(getQueryClient());
  });
});
