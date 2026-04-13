import { Body, Controller, Get, Post, Request, UseGuards } from "@nestjs/common";
import {
  ApiBearerAuth,
  ApiBody,
  ApiOperation,
  ApiResponse,
  ApiTags,
} from "@nestjs/swagger";

import { AuthService } from "./auth.service";
import { LoginDto } from "./dto/login.dto";
import { RegisterDto } from "./dto/register.dto";
import { JwtAuthGuard } from "./guards/jwt-auth.guard";

@ApiTags("auth")
@Controller("auth")
export class AuthController {
  constructor(private readonly authService: AuthService) {}

  @Post("register")
  @ApiOperation({ summary: "Register a new user" })
  @ApiBody({ type: RegisterDto })
  @ApiResponse({
    status: 201,
    description: "User registered successfully",
    schema: {
      example: {
        access_token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
        user: {
          id: "507f1f77bcf86cd799439011",
          name: "John Doe",
          email: "john@example.com",
          roles: [],
          emailVerified: false,
        },
      },
    },
  })
  @ApiResponse({ status: 400, description: "Invalid input" })
  @ApiResponse({ status: 409, description: "User already exists" })
  async register(@Body() registerDto: RegisterDto) {
    return this.authService.register(registerDto);
  }

  @Post("login")
  @ApiOperation({ summary: "Login with email and password" })
  @ApiBody({ type: LoginDto })
  @ApiResponse({
    status: 200,
    description: "Login successful",
    schema: {
      example: {
        access_token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
        user: {
          id: "507f1f77bcf86cd799439011",
          name: "John Doe",
          email: "john@example.com",
          roles: [],
          emailVerified: true,
        },
      },
    },
  })
  @ApiResponse({ status: 401, description: "Invalid credentials" })
  async login(@Body() loginDto: LoginDto) {
    return this.authService.login(loginDto);
  }

  @UseGuards(JwtAuthGuard)
  @Get("session")
  @ApiBearerAuth("JWT-auth")
  @ApiOperation({ summary: "Get current authenticated user" })
  @ApiResponse({
    status: 200,
    description: "Current user session",
    schema: {
      example: {
        user: {
          id: "507f1f77bcf86cd799439011",
          name: "John Doe",
          email: "john@example.com",
          roles: [],
          emailVerified: true,
        },
      },
    },
  })
  @ApiResponse({ status: 401, description: "Unauthorized" })
  async getSession(@Request() req: { user: { userId: string } }) {
    return {
      user: await this.authService.validateUser(req.user.userId),
    };
  }
}
