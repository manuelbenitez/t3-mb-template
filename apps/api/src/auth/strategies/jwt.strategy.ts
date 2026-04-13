import { ForbiddenException, Injectable, UnauthorizedException } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { InjectModel } from "@nestjs/mongoose";
import { PassportStrategy } from "@nestjs/passport";
import { Model } from "mongoose";
import { ExtractJwt, Strategy } from "passport-jwt";

import { User, UserDocument } from "../../users/schemas/user.schema";

export interface JwtPayload {
  sub: string;
  email: string;
}

@Injectable()
export class JwtStrategy extends PassportStrategy(Strategy) {
  constructor(
    private configService: ConfigService,
    @InjectModel(User.name) private userModel: Model<UserDocument>,
  ) {
    super({
      jwtFromRequest: ExtractJwt.fromAuthHeaderAsBearerToken(),
      ignoreExpiration: false,
      secretOrKey:
        configService.get<string>("JWT_SECRET") ??
        "change-me-use-openssl-rand-base64-32",
    });
  }

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
      isAdmin: user.isAdmin,
    };
  }
}
