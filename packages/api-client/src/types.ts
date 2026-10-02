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

export interface AuthResponse {
  access_token: string;
  user: Omit<User, "accountStatus">;
}

export interface SessionResponse {
  user: User;
}
