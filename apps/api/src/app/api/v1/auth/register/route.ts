import { NextResponse } from "next/server";
import { db } from "@/db/client";
import { users } from "@/db/schema";
import { createSession, getOrCreateSettings, hashPassword } from "@/lib/auth";
import { ApiError, handler, parseBody } from "@/lib/http";
import { registerSchema } from "@/lib/validation";

export const runtime = "nodejs";

export const POST = handler(async (request: Request) => {
  const body = await parseBody(request, registerSchema);

  const existing = await db.query.users.findFirst();
  if (existing) {
    throw new ApiError(
      409,
      "account_exists",
      "An account already exists on this server. Sign in with it instead.",
    );
  }

  const [user] = await db
    .insert(users)
    .values({ email: body.email, passwordHash: await hashPassword(body.password) })
    .returning();
  if (!user) throw new ApiError(500, "internal_error", "Could not create user");

  await getOrCreateSettings(user.id);
  const token = await createSession(user.id, null);

  return NextResponse.json({ token, user: { id: user.id, email: user.email } }, { status: 201 });
});
