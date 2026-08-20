import { NextResponse } from "next/server";
import { db } from "@/db/client";
import { createSession, verifyPassword } from "@/lib/auth";
import { ApiError, handler, parseBody } from "@/lib/http";
import { loginSchema } from "@/lib/validation";

export const runtime = "nodejs";

export const POST = handler(async (request: Request) => {
  const body = await parseBody(request, loginSchema);

  // `body.email` arrives trimmed and lower-cased from the schema; compare
  // case-insensitively so an account registered before that normalisation
  // (stored with whatever casing was typed) still matches. The callback form
  // hands back the query builder's own aliased column, so the generated SQL
  // stays valid.
  const user = await db.query.users.findFirst({
    where: (table, { sql }) => sql`lower(${table.email}) = ${body.email}`,
  });
  if (!user || !(await verifyPassword(user.passwordHash, body.password))) {
    throw new ApiError(401, "invalid_credentials", "Email or password is incorrect");
  }

  const token = await createSession(user.id, body.deviceName ?? null);
  return NextResponse.json({ token, user: { id: user.id, email: user.email } });
});
