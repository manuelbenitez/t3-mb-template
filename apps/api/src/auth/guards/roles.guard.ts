import type { CanActivate, ExecutionContext } from "@nestjs/common";
import { ForbiddenException, Injectable } from "@nestjs/common";
import { Reflector } from "@nestjs/core";

import type { Role } from "../../users/schemas/user.schema";
import { ROLES_KEY } from "../decorators/roles.decorator";

/**
 * Enforces `@Roles()`. Registered globally after JwtAuthGuard, so request.user is
 * set on every non-public route.
 */
@Injectable()
export class RolesGuard implements CanActivate {
  constructor(private reflector: Reflector) {}

  /**
   * Allows the request when the route needs no role or the user holds one of them.
   *
   * @param context - The current request context.
   * @returns True when access is allowed.
   * @throws {ForbiddenException} When the user holds none of the required roles.
   */
  canActivate(context: ExecutionContext): boolean {
    const required = this.reflector.getAllAndOverride<Role[] | undefined>(
      ROLES_KEY,
      [context.getHandler(), context.getClass()],
    );
    if (!required || required.length === 0) {
      return true;
    }
    const user = context
      .switchToHttp()
      .getRequest<{ user?: { roles?: Role[] } }>().user;
    if (!user?.roles?.some((role) => required.includes(role))) {
      throw new ForbiddenException("Insufficient role");
    }
    return true;
  }
}
