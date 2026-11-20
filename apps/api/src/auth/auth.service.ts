import { Injectable, UnauthorizedException } from "@nestjs/common";
import { JwtService } from "@nestjs/jwt";
import * as bcrypt from "bcrypt";

import { UsersService } from "../users/users.service";
import { LoginDto } from "./dto/login.dto";
import { RegisterDto } from "./dto/register.dto";

/** Account creation, credential checks and token signing. */
@Injectable()
export class AuthService {
  constructor(
    private usersService: UsersService,
    private jwtService: JwtService,
  ) {}

  /**
   * Creates the user and signs a token for them.
   *
   * @param registerDto - Name, email and password.
   * @returns The access token and the public user.
   */
  async register(registerDto: RegisterDto) {
    const user = await this.usersService.create({
      name: registerDto.name,
      email: registerDto.email,
      password: registerDto.password,
    });

    const payload = { sub: user._id.toString(), email: user.email };

    return {
      access_token: this.jwtService.sign(payload),
      user: {
        id: user._id.toString(),
        name: user.name,
        email: user.email,
        roles: user.roles,
        emailVerified: user.emailVerified,
      },
    };
  }

  /**
   * Checks the email and password and signs a token.
   *
   * @param loginDto - Email and password.
   * @returns The access token and the public user.
   * @throws {UnauthorizedException} When the email is unknown or the password is wrong.
   */
  async login(loginDto: LoginDto) {
    const user = await this.usersService.findByEmail(loginDto.email);

    if (!user) {
      throw new UnauthorizedException("Invalid credentials");
    }

    const isPasswordValid = await bcrypt.compare(
      loginDto.password,
      user.password,
    );

    if (!isPasswordValid) {
      throw new UnauthorizedException("Invalid credentials");
    }

    const payload = { sub: user._id.toString(), email: user.email };

    return {
      access_token: this.jwtService.sign(payload),
      user: {
        id: user._id.toString(),
        name: user.name,
        email: user.email,
        roles: user.roles,
        emailVerified: user.emailVerified,
      },
    };
  }

  /**
   * Loads the user a token belongs to.
   *
   * @param userId - The token's subject.
   * @returns The user.
   */
  async validateUser(userId: string) {
    return this.usersService.findById(userId);
  }
}
