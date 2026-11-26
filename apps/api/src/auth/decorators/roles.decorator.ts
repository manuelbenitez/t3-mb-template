import { SetMetadata } from "@nestjs/common";
import type { Role } from "../../users/schemas/user.schema";

/** Metadata key holding the roles a route requires. */
export const ROLES_KEY = "roles";

/**
 * Requires at least one of the given roles. Enforced by the global RolesGuard.
 *
 * @param roles - Roles that grant access; any one is enough.
 * @returns The metadata decorator.
 */
export const Roles = (...roles: Role[]) => SetMetadata(ROLES_KEY, roles);
