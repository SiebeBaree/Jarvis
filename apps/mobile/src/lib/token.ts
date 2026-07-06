import * as SecureStore from 'expo-secure-store';
import { Platform } from 'react-native';

/** Key under which the single long-lived API bearer token is stored. */
export const TOKEN_KEY = 'jarvis_api_token';

/**
 * SecureStore is not available on web. Fall back to localStorage there so that
 * `expo start --web` doesn't crash. On native we always use SecureStore.
 */
const isWeb = Platform.OS === 'web';

export async function getToken(): Promise<string | null> {
  if (isWeb) {
    if (typeof localStorage === 'undefined') return null;
    return localStorage.getItem(TOKEN_KEY);
  }
  return SecureStore.getItemAsync(TOKEN_KEY);
}

export async function setToken(token: string): Promise<void> {
  if (isWeb) {
    if (typeof localStorage === 'undefined') return;
    localStorage.setItem(TOKEN_KEY, token);
    return;
  }
  await SecureStore.setItemAsync(TOKEN_KEY, token);
}

export async function clearToken(): Promise<void> {
  if (isWeb) {
    if (typeof localStorage === 'undefined') return;
    localStorage.removeItem(TOKEN_KEY);
    return;
  }
  await SecureStore.deleteItemAsync(TOKEN_KEY);
}
