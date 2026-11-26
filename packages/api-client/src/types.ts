/** A user as the API serializes it: no password, `_id` exposed as `id`. */
export interface User {
  id: string;
  name: string;
  email: string;
  roles: ("user" | "admin")[];
  emailVerified: boolean;
  accountStatus: "active" | "paused" | "suspended";
  image?: string;
  createdAt?: string;
  updatedAt?: string;
}

/** Response of register and login. */
export interface AuthResponse {
  access_token: string;
  user: Omit<User, "accountStatus">;
}

/** Response of `GET /api/auth/session`. */
export interface SessionResponse {
  user: User;
}
