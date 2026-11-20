import { IsEmail, IsNotEmpty, IsString, MinLength } from "class-validator";

/** Input to UsersService.create; the password arrives in plain text and is hashed there. */
export class CreateUserDto {
  @IsString()
  @IsNotEmpty()
  name: string;

  @IsEmail()
  @IsNotEmpty()
  email: string;

  @IsString()
  @MinLength(6)
  password: string;
}
