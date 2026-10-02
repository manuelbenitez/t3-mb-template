import type { ExecutionContext } from "@nestjs/common";
import { Controller, ForbiddenException, Get } from "@nestjs/common";
import { Reflector } from "@nestjs/core";
import { describe, expect, it } from "vitest";

import { Public } from "../decorators/public.decorator";
import { Roles } from "../decorators/roles.decorator";
import { JwtAuthGuard } from "./jwt-auth.guard";
import { RolesGuard } from "./roles.guard";

@Public()
@Controller()
class PublicController {
  @Get()
  open() {}
}

@Controller()
class MixedController {
  @Public()
  @Get()
  open() {}

  @Roles("admin")
  @Get()
  adminOnly() {}

  @Get()
  anyUser() {}
}

function ctx(
  cls: new () => object,
  handler: string,
  user?: { roles: string[] },
): ExecutionContext {
  return {
    getClass: () => cls,
    getHandler: () => (cls.prototype as Record<string, unknown>)[handler],
    switchToHttp: () => ({ getRequest: () => ({ user }) }),
  } as unknown as ExecutionContext;
}

describe("JwtAuthGuard", () => {
  const guard = new JwtAuthGuard(new Reflector());

  it("lets a class-level @Public() controller through", () => {
    expect(guard.canActivate(ctx(PublicController, "open"))).toBe(true);
  });

  it("lets a handler-level @Public() route through", () => {
    expect(guard.canActivate(ctx(MixedController, "open"))).toBe(true);
  });
});

describe("RolesGuard", () => {
  const guard = new RolesGuard(new Reflector());

  it("allows a route without @Roles()", () => {
    expect(
      guard.canActivate(ctx(MixedController, "anyUser", { roles: ["user"] })),
    ).toBe(true);
  });

  it("allows a user holding the required role", () => {
    expect(
      guard.canActivate(
        ctx(MixedController, "adminOnly", { roles: ["user", "admin"] }),
      ),
    ).toBe(true);
  });

  it("forbids a user without the required role", () => {
    expect(() =>
      guard.canActivate(ctx(MixedController, "adminOnly", { roles: ["user"] })),
    ).toThrow(ForbiddenException);
  });

  it("forbids when no user is attached", () => {
    expect(() => guard.canActivate(ctx(MixedController, "adminOnly"))).toThrow(
      ForbiddenException,
    );
  });
});
