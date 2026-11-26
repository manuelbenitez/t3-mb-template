import { ApiClient, createAuthClient } from "@acme/api-client";
import { env } from "~/env";

/**
 * Reads the stored access token; there is none during server rendering.
 *
 * @returns The token, or null.
 */
function getToken(): string | null {
  if (typeof window === "undefined") return null;
  return localStorage.getItem("access_token");
}

/** The portal's API client, sending the stored token. */
export const apiClient = new ApiClient({
  baseUrl: env.NEXT_PUBLIC_API_URL,
  getToken,
});

/** The auth endpoints, bound to apiClient. */
export const authApi = createAuthClient(apiClient);
