import { Module } from "@nestjs/common";
import { ConfigModule, ConfigService } from "@nestjs/config";
import { MongooseModule } from "@nestjs/mongoose";

import { AuthModule } from "./auth/auth.module";
import { UsersModule } from "./users/users.module";

@Module({
  imports: [
    // Environment configuration — global so all modules can inject ConfigService
    ConfigModule.forRoot({
      isGlobal: true,
      envFilePath: "../../.env",
    }),

    // MongoDB connection
    MongooseModule.forRootAsync({
      imports: [ConfigModule],
      useFactory: (configService: ConfigService) => ({
        uri:
          configService.get<string>("MONGODB_URI") ??
          "mongodb://localhost:27017/myapp",
      }),
      inject: [ConfigService],
    }),

    // Feature modules
    AuthModule,
    UsersModule,
  ],
})
export class AppModule {}
