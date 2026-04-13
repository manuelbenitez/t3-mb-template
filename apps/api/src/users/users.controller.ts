import { Controller, Get, Query, Request, UseGuards } from "@nestjs/common";
import {
  ApiBearerAuth,
  ApiOperation,
  ApiResponse,
  ApiTags,
} from "@nestjs/swagger";

import { JwtAuthGuard } from "../auth/guards/jwt-auth.guard";
import { UsersService } from "./users.service";

@ApiTags("users")
@ApiBearerAuth("JWT-auth")
@UseGuards(JwtAuthGuard)
@Controller("users")
export class UsersController {
  constructor(private readonly usersService: UsersService) {}

  @Get("me")
  @ApiOperation({ summary: "Get current user profile" })
  @ApiResponse({ status: 200, description: "User profile" })
  @ApiResponse({ status: 401, description: "Unauthorized" })
  async getProfile(@Request() req: { user: { userId: string } }) {
    return this.usersService.findById(req.user.userId);
  }

  @Get()
  @ApiOperation({ summary: "List all users (optionally filter by role)" })
  @ApiResponse({ status: 200, description: "List of users" })
  @ApiResponse({ status: 401, description: "Unauthorized" })
  async findAll(@Query("role") role?: "GP" | "LP") {
    return this.usersService.findAll(role);
  }
}
