import {
  ForbiddenException,
  Injectable,
  UnauthorizedException,
} from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { InjectModel } from "@nestjs/mongoose";
import { PassportStrategy } from "@nestjs/passport";
import { Model } from "mongoose";
import { ExtractJwt, Strategy } from "passport-jwt";

import { User, UserDocument } from "../../users/schemas/user.schema";

/** Claims signed into every access token. */
export interface JwtPayload {
  sub: string;
  email: string;
}

/** Passport strategy that verifies the bearer token and loads the account behind it. */
@Injectable()
export class JwtStrategy extends PassportStrategy(Strategy) {
  constructor(
    private configService: ConfigService,
    @InjectModel(User.name) private userModel: Model<UserDocument>,
  ) {
    super({
      jwtFromRequest: ExtractJwt.fromAuthHeaderAsBearerToken(),
      ignoreExpiration: false,
      secretOrKey: configService.getOrThrow<string>("JWT_SECRET"),
    });
  }

  /**
   * Resolves a verified token to the user attached to the request.
   *
   * @param payload - The verified token claims.
   * @returns The user id, email and roles.
   * @throws {UnauthorizedException} When the claims are incomplete or the user no longer exists.
   * @throws {ForbiddenException} When the account is paused or suspended.
   */
  async validate(payload: JwtPayload) {
    if (!payload.sub || !payload.email) {
      throw new UnauthorizedException();
    }

    const user = await this.userModel.findById(payload.sub).exec();
    if (!user) {
      throw new UnauthorizedException("User not found");
    }

    if (user.accountStatus !== "active") {
      throw new ForbiddenException(
        `Your account has been ${user.accountStatus}. Please contact support.`,
      );
    }

    return {
      userId: payload.sub,
      email: payload.email,
      roles: user.roles,
    };
  }
}
