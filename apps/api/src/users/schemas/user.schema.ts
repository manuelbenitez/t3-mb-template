import { Prop, Schema, SchemaFactory } from "@nestjs/mongoose";
import { Document } from "mongoose";

export type UserDocument = User & Document;

@Schema({ timestamps: true })
export class User extends Document {
  @Prop({ required: true, type: String })
  name: string;

  @Prop({ required: true, unique: true, type: String })
  email: string;

  @Prop({ required: true, type: String })
  password: string;

  /**
   * Extensible roles array. Default values: "GP" (General Partner) and "LP" (Limited Partner).
   * Extend the enum for your domain: e.g. ["admin", "member", "viewer"].
   */
  @Prop({ type: [String], enum: ["GP", "LP"], default: [] })
  roles: ("GP" | "LP")[];

  @Prop({ default: false, type: Boolean })
  emailVerified: boolean;

  @Prop({ default: false, type: Boolean })
  isAdmin: boolean;

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

export const UserSchema = SchemaFactory.createForClass(User);

// Strip password and normalize _id on every JSON serialization
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

UserSchema.index({ email: 1 });
