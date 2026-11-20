import { z } from "zod";

/** The login form: a valid email and a non-empty password. */
export const loginSchema = z.object({
  email: z.email("Invalid email address"),
  password: z.string().min(1, "Password is required"),
});

/** The register form; the 6-character password minimum matches RegisterDto in the API. */
export const registerSchema = z.object({
  name: z.string().min(1, "Name is required"),
  email: z.email("Invalid email address"),
  password: z.string().min(6, "Password must be at least 6 characters"),
});

/** Values of a valid login form. */
export type LoginInput = z.infer<typeof loginSchema>;

/** Values of a valid register form. */
export type RegisterInput = z.infer<typeof registerSchema>;
