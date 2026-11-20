import { ApiProperty } from "@nestjs/swagger";
import { IsEmail, IsNotEmpty, IsString } from "class-validator";

/** Body of `POST /api/auth/login`. */
export class LoginDto {
  @ApiProperty({
    example: "john@example.com",
    description: "User email address",
  })
  @IsEmail()
  @IsNotEmpty()
  email: string;

  @ApiProperty({
    example: "password123",
    description: "User password",
    minLength: 6,
  })
  @IsString()
  @IsNotEmpty()
  password: string;
}
