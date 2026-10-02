import { MongoMemoryServer } from "mongodb-memory-server";
import type { INestApplication } from "@nestjs/common";
import { ValidationPipe } from "@nestjs/common";
import { Test } from "@nestjs/testing";
import { HttpExceptionFilter } from "../common/filters/http-exception.filter";

export const TEST_JWT_SECRET = "test-secret-at-least-32-characters-long!!";

export interface TestApp {
  app: INestApplication;
  close: () => Promise<void>;
}

// Boots the real AppModule against an in-memory MongoDB with the same global
// pipes, filter and prefix as main.ts.
export async function createTestApp(): Promise<TestApp> {
  const mongo = await MongoMemoryServer.create();
  process.env.MONGODB_URI = mongo.getUri();
  process.env.JWT_SECRET = TEST_JWT_SECRET;

  const { AppModule } = await import("../app.module.js");
  const moduleRef = await Test.createTestingModule({
    imports: [AppModule],
  }).compile();

  const app = moduleRef.createNestApplication();
  app.useGlobalFilters(new HttpExceptionFilter());
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
    }),
  );
  app.setGlobalPrefix("api");
  await app.init();

  return {
    app,
    close: async () => {
      await app.close();
      await mongo.stop();
    },
  };
}
