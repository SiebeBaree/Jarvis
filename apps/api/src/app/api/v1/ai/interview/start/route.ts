import { NextResponse } from "next/server";
import { startInterview } from "@/lib/ai/interview";
import { requireAuth } from "@/lib/auth";
import { ApiError, handler } from "@/lib/http";
import { interviewStartSchema } from "@/lib/validation";

export const runtime = "nodejs";
export const maxDuration = 180; // deep model calls are slow

/** Like parseBody but tolerates an empty body (kind defaults to onboarding). */
async function parseStartBody(request: Request): Promise<{ kind: string }> {
  const text = await request.text();
  let raw: unknown = {};
  if (text.trim()) {
    try {
      raw = JSON.parse(text);
    } catch {
      throw new ApiError(400, "invalid_json", "Request body must be valid JSON");
    }
  }
  const result = interviewStartSchema.safeParse(raw);
  if (!result.success) {
    throw new ApiError(
      400,
      "validation_error",
      result.error.issues.map((i) => i.message).join("; "),
    );
  }
  return result.data;
}

export const POST = handler(async (request: Request) => {
  const ctx = await requireAuth(request);
  const body = await parseStartBody(request);

  const { session, round } = await startInterview(ctx.userId, body.kind, ctx.settings.aiOverrides);
  return NextResponse.json({ sessionId: session.id, round });
});
