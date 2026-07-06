import type { z } from "zod";

/** Small wrapper around `Response.json` for consistent JSON responses. */
export function json(data: unknown, init?: ResponseInit): Response {
  return Response.json(data, init);
}

/**
 * Thrown as a control-flow signal carrying an HTTP `Response`. Route handlers
 * catch this and return the wrapped response.
 */
export class HttpError extends Error {
  constructor(public readonly response: Response) {
    super("HttpError");
  }
}

/**
 * Parses and validates a JSON request body against `schema`. Throws an
 * {@link HttpError} wrapping a 400 JSON `Response` on invalid JSON or a
 * schema mismatch.
 */
export async function parseBody<T>(
  req: Request,
  schema: z.ZodType<T>,
): Promise<T> {
  let body: unknown;
  try {
    body = await req.json();
  } catch {
    throw new HttpError(json({ error: "invalid JSON body" }, { status: 400 }));
  }

  const result = schema.safeParse(body);
  if (!result.success) {
    throw new HttpError(
      json(
        { error: "invalid body", issues: result.error.issues },
        { status: 400 },
      ),
    );
  }
  return result.data;
}
