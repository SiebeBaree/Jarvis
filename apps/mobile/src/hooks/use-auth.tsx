import { createContext, useCallback, useContext, useEffect, useMemo, useState } from 'react';

import { setUnauthorizedHandler } from '@/lib/api';
import { clearToken as clearStoredToken, getToken, setToken as setStoredToken } from '@/lib/token';

type AuthContextValue = {
  /** The current API token, or null when signed out. */
  token: string | null;
  /** True while the persisted token is being loaded on first mount. */
  isLoading: boolean;
  /** Persist a token and mark the app as authenticated. */
  setToken: (token: string) => Promise<void>;
  /** Remove the token and route back to setup. */
  clearToken: () => Promise<void>;
};

const AuthContext = createContext<AuthContextValue | null>(null);

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [token, setTokenState] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    let active = true;
    getToken()
      .then((stored) => {
        if (active) setTokenState(stored);
      })
      .finally(() => {
        if (active) setIsLoading(false);
      });
    return () => {
      active = false;
    };
  }, []);

  const setToken = useCallback(async (next: string) => {
    await setStoredToken(next);
    setTokenState(next);
  }, []);

  const clearToken = useCallback(async () => {
    await clearStoredToken();
    setTokenState(null);
  }, []);

  // A 401 from anywhere clears the token, which trips the auth gate to setup.
  useEffect(() => {
    setUnauthorizedHandler(() => {
      void clearToken();
    });
    return () => setUnauthorizedHandler(null);
  }, [clearToken]);

  const value = useMemo<AuthContextValue>(
    () => ({ token, isLoading, setToken, clearToken }),
    [token, isLoading, setToken, clearToken],
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth(): AuthContextValue {
  const context = useContext(AuthContext);
  if (context === null) {
    throw new Error('useAuth must be used within an AuthProvider');
  }
  return context;
}
