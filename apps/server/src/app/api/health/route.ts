import { json } from "@/lib/api";

export function GET(): Response {
  return json({ ok: true });
}
