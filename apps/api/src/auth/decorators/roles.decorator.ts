import { SetMetadata } from "@nestjs/common";
import type { Role } from "../../users/schemas/user.schema";

export const ROLES_KEY = "roles";

/**
 * Require at least one of the given roles. Enforced by the global RolesGuard.
 */
export const Roles = (...roles: Role[]) => SetMetadata(ROLES_KEY, roles);
