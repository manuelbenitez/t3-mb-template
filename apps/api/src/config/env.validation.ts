const MIN_JWT_SECRET_LENGTH = 32;
// The .env.example value: long enough to pass the length check, but public.
const PLACEHOLDER_JWT_SECRET = "change-me-use-openssl-rand-base64-32";

export interface Env {
  MONGODB_URI: string;
  JWT_SECRET: string;
}

// Fails boot on a missing or weak secret instead of falling back to a
// well-known default.
export function validateEnv(config: Record<string, unknown>): Env {
  const errors: string[] = [];
  const mongoUri = config.MONGODB_URI;
  const jwtSecret = config.JWT_SECRET;

  if (typeof mongoUri !== "string" || !/^mongodb(\+srv)?:\/\//.test(mongoUri)) {
    errors.push("MONGODB_URI must be a mongodb:// or mongodb+srv:// URI");
  }
  if (
    typeof jwtSecret !== "string" ||
    jwtSecret.length < MIN_JWT_SECRET_LENGTH ||
    jwtSecret === PLACEHOLDER_JWT_SECRET
  ) {
    errors.push(
      `JWT_SECRET must be at least ${MIN_JWT_SECRET_LENGTH} characters and not the .env.example placeholder (openssl rand -base64 32)`,
    );
  }
  if (errors.length > 0) {
    throw new Error(`Invalid environment:\n- ${errors.join("\n- ")}`);
  }
  return { ...config, MONGODB_URI: mongoUri, JWT_SECRET: jwtSecret } as Env;
}
