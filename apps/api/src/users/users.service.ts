import {
  ConflictException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import { InjectModel } from "@nestjs/mongoose";
import * as bcrypt from "bcrypt";
import { Model } from "mongoose";

import { CreateUserDto } from "./dto/create-user.dto";
import { Role, User, UserDocument } from "./schemas/user.schema";

/** Reads and writes user accounts. */
@Injectable()
export class UsersService {
  constructor(@InjectModel(User.name) private userModel: Model<UserDocument>) {}

  /**
   * Stores a new user with a bcrypt-hashed password.
   *
   * @param createUserDto - Name, email and plain-text password.
   * @returns The saved user.
   * @throws {ConflictException} When the email is already registered.
   */
  async create(createUserDto: CreateUserDto): Promise<UserDocument> {
    const existingUser = await this.userModel.findOne({
      email: createUserDto.email,
    });

    if (existingUser) {
      throw new ConflictException("User with this email already exists");
    }

    const hashedPassword = await bcrypt.hash(createUserDto.password, 10);

    const user = new this.userModel({
      ...createUserDto,
      password: hashedPassword,
    });

    return user.save();
  }

  /**
   * Finds a user by email, password hash included.
   *
   * @param email - The email to look up.
   * @returns The user, or null when none matches.
   */
  async findByEmail(email: string): Promise<UserDocument | null> {
    return this.userModel.findOne({ email }).exec();
  }

  /**
   * Finds a user by id.
   *
   * @param id - The user id.
   * @returns The user.
   * @throws {NotFoundException} When no user has this id.
   */
  async findById(id: string): Promise<UserDocument> {
    const user = await this.userModel.findById(id).exec();

    if (!user) {
      throw new NotFoundException("User not found");
    }

    return user;
  }

  /**
   * Lists users, optionally only those holding a role.
   *
   * @param role - Only return users holding this role.
   * @returns The users, without password hashes.
   */
  async findAll(role?: Role): Promise<User[]> {
    const filter = role ? { roles: role } : {};
    return this.userModel.find(filter).select("-password").exec();
  }
}
