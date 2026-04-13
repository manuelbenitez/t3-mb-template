import type { ExecutionContext } from "@nestjs/common";
import { createParamDecorator } from "@nestjs/common";

export const GetUser = createParamDecorator(
  (_data: unknown, ctx: ExecutionContext) => {
    const request = ctx.switchToHttp().getRequest<{ user: unknown }>();
    return request.user;
  },
);
