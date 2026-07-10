import { NextResponse } from "next/server";
import { eq } from "drizzle-orm";
import { db } from "@/db/client";
import { users } from "@/db/schema";
import { createSession, verifyPassword } from "@/lib/auth";
import { ApiError, handler, parseBody } from "@/lib/http";
import { loginSchema } from "@/lib/validation";

export const runtime = "nodejs";

export const POST = handler(async (request: Request) => {
  const body = await parseBody(request, loginSchema);

  const user = await db.query.users.findFirst({ where: eq(users.email, body.email) });
  if (!user || !(await verifyPassword(user.passwordHash, body.password))) {
    throw new ApiError(401, "invalid_credentials", "Email or password is incorrect");
  }

  const token = await createSession(user.id, body.deviceName ?? null);
  return NextResponse.json({ token, user: { id: user.id, email: user.email } });
});
