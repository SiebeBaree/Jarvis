import { getToken } from '@/lib/token';

/** Default API URL for local development when the env var is not set. */
const DEFAULT_API_URL = 'http://localhost:3001';

export function getApiUrl(): string {
  return process.env.EXPO_PUBLIC_API_URL ?? DEFAULT_API_URL;
}

export class ApiError extends Error {
  readonly status: number;

  constructor(status: number, message: string) {
    super(message);
    this.name = 'ApiError';
    this.status = status;
  }
}

/**
 * Module-level 401 handler. The root layout registers this so that an expired
 * or invalid token can route the app back to the setup screen from anywhere.
 */
let onUnauthorized: (() => void) | null = null;

export function setUnauthorizedHandler(handler: (() => void) | null): void {
  onUnauthorized = handler;
}

type ApiInit = {
  method?: 'GET' | 'POST' | 'PUT' | 'PATCH' | 'DELETE';
  body?: unknown;
  /** Override the stored token, e.g. to validate a token before persisting it. */
  token?: string;
};

export async function apiFetch<T>(path: string, init?: ApiInit): Promise<T> {
  const token = init?.token ?? (await getToken());
  const url = `${getApiUrl()}${path}`;

  const headers: Record<string, string> = {
    Accept: 'application/json',
  };
  if (token) {
    headers.Authorization = `Bearer ${token}`;
  }
  if (init?.body !== undefined) {
    headers['Content-Type'] = 'application/json';
  }

  const response = await fetch(url, {
    method: init?.method ?? 'GET',
    headers,
    body: init?.body !== undefined ? JSON.stringify(init.body) : undefined,
  });

  if (response.status === 401) {
    onUnauthorized?.();
    throw new ApiError(401, 'Unauthorized');
  }

  if (!response.ok) {
    const message = await readErrorMessage(response);
    throw new ApiError(response.status, message);
  }

  if (response.status === 204) {
    return undefined as T;
  }

  return (await response.json()) as T;
}

async function readErrorMessage(response: Response): Promise<string> {
  try {
    const data: unknown = await response.json();
    if (
      data !== null &&
      typeof data === 'object' &&
      'message' in data &&
      typeof (data as { message: unknown }).message === 'string'
    ) {
      return (data as { message: string }).message;
    }
  } catch {
    // Body was not JSON; fall through to the status text.
  }
  return response.statusText || `Request failed with status ${response.status}`;
}
