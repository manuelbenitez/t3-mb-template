import { ApiClient, createAuthClient } from "@acme/api-client";

import { env } from "~/env";

function getToken(): string | null {
  if (typeof window === "undefined") return null;
  return localStorage.getItem("access_token");
}

export const apiClient = new ApiClient({
  baseUrl: env.NEXT_PUBLIC_API_URL,
  getToken,
});

export const authApi = createAuthClient(apiClient);
