export interface User {
  id: string;
  name: string;
  email: string;
  roles: ("GP" | "LP")[];
  emailVerified: boolean;
  isAdmin: boolean;
  accountStatus: "active" | "paused" | "suspended";
  image?: string;
  createdAt?: string;
  updatedAt?: string;
}

export interface AuthResponse {
  access_token: string;
  user: Omit<User, "isAdmin" | "accountStatus">;
}

export interface SessionResponse {
  user: User;
}
