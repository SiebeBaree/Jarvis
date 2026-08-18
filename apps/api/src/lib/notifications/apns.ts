// Sending to Apple Push Notification service.
//
// APNs speaks HTTP/2 only, and Node's global fetch negotiates HTTP/1.1, so this
// goes through node:http2 directly. That is also why there is no push SDK here:
// the whole protocol surface we need is one POST per device, once a day.

import { connect, constants } from "node:http2";
import { SignJWT, importPKCS8 } from "jose";
import { ApiError } from "../http";

const APNS_HOSTS = {
  production: "https://api.push.apple.com",
  sandbox: "https://api.sandbox.push.apple.com",
} as const;

export type ApnsEnvironment = keyof typeof APNS_HOSTS;

export type ApnsPayload = {
  title: string;
  body: string;
  /** Travels in the payload so the app knows why it was woken. */
  kind: string;
  dayKey: string;
};

export type ApnsResult =
  | { ok: true }
  /** The token is dead. The caller revokes the device row. */
  | { ok: false; unregistered: true; status: number; reason: string }
  | { ok: false; unregistered: false; status: number; reason: string };

const REQUEST_TIMEOUT_MS = 10_000;
// Apple accepts a provider token for an hour and rejects one minted too often.
// Well inside the window, and module scope means a warm lambda reuses it.
const TOKEN_TTL_MS = 45 * 60 * 1000;

let cachedToken: { jwt: string; mintedAt: number } | null = null;

function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new ApiError(500, "apns_not_configured", `${name} is not set`);
  }
  return value;
}

/** The .p8 is stored base64 so a multiline PEM survives the env var round trip. */
function privateKeyPem(): string {
  const raw = requireEnv("APNS_PRIVATE_KEY_BASE64");
  const pem = Buffer.from(raw, "base64").toString("utf8");
  if (!pem.includes("BEGIN PRIVATE KEY")) {
    throw new ApiError(
      500,
      "apns_not_configured",
      "APNS_PRIVATE_KEY_BASE64 does not decode to a PKCS8 PEM",
    );
  }
  return pem;
}

export async function providerToken(now = Date.now()): Promise<string> {
  if (cachedToken && now - cachedToken.mintedAt < TOKEN_TTL_MS) return cachedToken.jwt;

  const keyId = requireEnv("APNS_KEY_ID");
  const teamId = requireEnv("APNS_TEAM_ID");
  const key = await importPKCS8(privateKeyPem(), "ES256");

  const jwt = await new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: keyId })
    .setIssuer(teamId)
    .setIssuedAt(Math.floor(now / 1000))
    .sign(key);

  cachedToken = { jwt, mintedAt: now };
  return jwt;
}

/** Only for tests and for forcing a fresh token after a credential change. */
export function resetProviderToken(): void {
  cachedToken = null;
}

function apnsTopic(): string {
  return process.env.APNS_BUNDLE_ID ?? "com.siebebaree.jarvis";
}

type Http2Response = { status: number; body: string };

function post(
  host: string,
  path: string,
  headers: Record<string, string>,
  body: string,
): Promise<Http2Response> {
  return new Promise((resolve, reject) => {
    const session = connect(host);
    let settled = false;

    const finish = (fn: () => void) => {
      if (settled) return;
      settled = true;
      session.close();
      fn();
    };

    session.on("error", (err) => finish(() => reject(err)));

    const request = session.request({
      [constants.HTTP2_HEADER_METHOD]: "POST",
      [constants.HTTP2_HEADER_PATH]: path,
      ...headers,
    });
    request.setTimeout(REQUEST_TIMEOUT_MS, () =>
      finish(() => reject(new Error("APNs request timed out"))),
    );

    let status = 0;
    let chunks = "";
    request.on("response", (h) => {
      status = Number(h[constants.HTTP2_HEADER_STATUS] ?? 0);
    });
    request.setEncoding("utf8");
    request.on("data", (chunk: string) => {
      chunks += chunk;
    });
    request.on("error", (err) => finish(() => reject(err)));
    request.on("end", () => finish(() => resolve({ status, body: chunks })));

    request.end(body);
  });
}

/**
 * A rejected token is the one failure worth acting on: Apple says 410 when a
 * token is gone for good, and 400 BadDeviceToken when it never belonged to this
 * topic (a sandbox token sent to the production host, most often).
 */
function isUnregistered(status: number, reason: string): boolean {
  if (status === 410) return true;
  return status === 400 && (reason === "BadDeviceToken" || reason === "DeviceTokenNotForTopic");
}

export async function sendPush(
  deviceToken: string,
  environment: ApnsEnvironment,
  payload: ApnsPayload,
): Promise<ApnsResult> {
  const jwt = await providerToken();
  const body = JSON.stringify({
    aps: {
      alert: { title: payload.title, body: payload.body },
      sound: "default",
    },
    jarvis: { kind: payload.kind, dayKey: payload.dayKey },
  });

  let response: Http2Response;
  try {
    response = await post(APNS_HOSTS[environment], `/3/device/${deviceToken}`, {
      authorization: `bearer ${jwt}`,
      "apns-topic": apnsTopic(),
      "apns-push-type": "alert",
      "apns-priority": "10",
      // A nudge about today is worthless tomorrow, so let it expire rather than
      // arrive at breakfast, and collapse retries onto one notification.
      "apns-expiration": String(Math.floor(Date.now() / 1000) + 4 * 60 * 60),
      "apns-collapse-id": payload.kind,
      "content-type": "application/json",
    }, body);
  } catch (err) {
    return {
      ok: false,
      unregistered: false,
      status: 0,
      reason: err instanceof Error ? err.message : "transport error",
    };
  }

  if (response.status === 200) return { ok: true };

  let reason = response.body;
  try {
    reason = (JSON.parse(response.body) as { reason?: string }).reason ?? response.body;
  } catch {
    // Non-JSON body: keep it as-is for the log.
  }
  return {
    ok: false,
    unregistered: isUnregistered(response.status, reason),
    status: response.status,
    reason,
  };
}
