import { Prop, Schema, SchemaFactory } from "@nestjs/mongoose";
import { Document } from "mongoose";

/** Every role a user can hold. Extend it for your domain; `@Roles()` and RolesGuard read this list. */
export const ROLES = ["user", "admin"] as const;

/** One of ROLES. */
export type Role = (typeof ROLES)[number];

/** A user as Mongoose returns it from a query. */
export type UserDocument = User & Document;

/** A user account. Mongoose sets createdAt and updatedAt. */
@Schema({ timestamps: true })
export class User extends Document {
  @Prop({ required: true, type: String })
  name: string;

  @Prop({ required: true, unique: true, type: String })
  email: string;

  @Prop({ required: true, type: String })
  password: string;

  @Prop({ type: [String], enum: ROLES, default: ["user"] })
  roles: Role[];

  @Prop({ default: false, type: Boolean })
  emailVerified: boolean;

  @Prop({
    type: String,
    enum: ["active", "paused", "suspended"],
    default: "active",
  })
  accountStatus: "active" | "paused" | "suspended";

  @Prop({ type: String })
  image?: string;

  @Prop({ type: Date })
  createdAt: Date;

  @Prop({ type: Date })
  updatedAt: Date;
}

/** The User schema. Its JSON form drops password and __v and exposes _id as id. */
export const UserSchema = SchemaFactory.createForClass(User);

/* eslint-disable @typescript-eslint/no-explicit-any */
UserSchema.set("toJSON", {
  transform: (_doc: any, ret: any) => {
    ret.id = ret._id?.toString() ?? ret._id;
    delete ret._id;
    delete ret.__v;
    delete ret.password;
    return ret;
  },
});
/* eslint-enable @typescript-eslint/no-explicit-any */
