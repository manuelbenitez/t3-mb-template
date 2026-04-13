import { SetMetadata } from "@nestjs/common";

/**
 * Mark a route as public — bypasses the global JwtAuthGuard.
 * Usage: @Public() on a controller method.
 */
export const Public = () => SetMetadata("isPublic", true);
