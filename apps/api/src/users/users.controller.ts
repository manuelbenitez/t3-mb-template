import { Controller, Get, Query, Request } from "@nestjs/common";
import {
  ApiBearerAuth,
  ApiOperation,
  ApiResponse,
  ApiTags,
} from "@nestjs/swagger";

import { Roles } from "../auth/decorators/roles.decorator";
import type { Role } from "./schemas/user.schema";
import { UsersService } from "./users.service";

/** The signed-in user's profile and the admin user list. */
@ApiTags("users")
@ApiBearerAuth("JWT-auth")
@Controller("users")
export class UsersController {
  constructor(private readonly usersService: UsersService) {}

  /**
   * Returns the signed-in user's profile.
   *
   * @param req - The request, carrying the user the JWT strategy attached.
   * @returns The user.
   */
  @Get("me")
  @ApiOperation({ summary: "Get current user profile" })
  @ApiResponse({ status: 200, description: "User profile" })
  @ApiResponse({ status: 401, description: "Unauthorized" })
  async getProfile(@Request() req: { user: { userId: string } }) {
    return this.usersService.findById(req.user.userId);
  }

  /**
   * Lists users, optionally only those holding a role. Admin only.
   *
   * @param role - Only return users holding this role.
   * @returns The users, without password hashes.
   */
  @Get()
  @Roles("admin")
  @ApiOperation({
    summary: "List all users (admin only; optional role filter)",
  })
  @ApiResponse({ status: 200, description: "List of users" })
  @ApiResponse({ status: 401, description: "Unauthorized" })
  @ApiResponse({ status: 403, description: "Not an admin" })
  async findAll(@Query("role") role?: Role) {
    return this.usersService.findAll(role);
  }
}
