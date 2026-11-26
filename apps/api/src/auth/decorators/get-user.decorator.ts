import { createParamDecorator } from "@nestjs/common";
import type { ExecutionContext } from "@nestjs/common";

/** Parameter decorator that injects the user the JWT strategy attached to the request. */
export const GetUser = createParamDecorator(
  (_data: unknown, ctx: ExecutionContext) => {
    const request = ctx.switchToHttp().getRequest<{ user: unknown }>();
    return request.user;
  },
);
