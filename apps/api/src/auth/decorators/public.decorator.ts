import { SetMetadata } from "@nestjs/common";

/** Metadata key that marks a route or controller as public. */
export const IS_PUBLIC_KEY = "isPublic";

/**
 * Opts a route or a whole controller out of the global JwtAuthGuard.
 *
 * @returns The metadata decorator.
 */
export const Public = () => SetMetadata(IS_PUBLIC_KEY, true);
