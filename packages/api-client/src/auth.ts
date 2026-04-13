import type { ApiClient } from "./client";
import type { AuthResponse, SessionResponse } from "./types";

export function createAuthClient(client: ApiClient) {
  return {
    login: (data: { email: string; password: string }) =>
      client.post<AuthResponse>("/api/auth/login", data),

    register: (data: { name: string; email: string; password: string }) =>
      client.post<AuthResponse>("/api/auth/register", data),

    getSession: () => client.get<SessionResponse>("/api/auth/session"),
  };
}
