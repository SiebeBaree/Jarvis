import { useState } from 'react';
import {
  ActivityIndicator,
  KeyboardAvoidingView,
  Platform,
  Pressable,
  StyleSheet,
  TextInput,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { ThemedText } from '@/components/themed-text';
import { ThemedView } from '@/components/themed-view';
import { MaxContentWidth, Spacing } from '@/constants/theme';
import { useAuth } from '@/hooks/use-auth';
import { useTheme } from '@/hooks/use-theme';
import { ApiError, apiFetch } from '@/lib/api';
import type { Settings } from '@/hooks/use-settings';

const ACCENT = '#3c87f7';

export default function SetupScreen() {
  const theme = useTheme();
  const { setToken } = useAuth();

  const [value, setValue] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [connecting, setConnecting] = useState(false);

  const trimmed = value.trim();
  const canSubmit = trimmed.length > 0 && !connecting;

  async function handleConnect() {
    if (!canSubmit) return;
    setError(null);
    setConnecting(true);

    try {
      // Validate the token before persisting it so an invalid token never
      // trips the auth gate into the tabs.
      await apiFetch('/api/health', { token: trimmed });
      await apiFetch<Settings>('/api/settings', { token: trimmed });
      // Persisting flips the auth state, which routes to the tabs via the guard.
      await setToken(trimmed);
    } catch (err) {
      if (err instanceof ApiError) {
        setError(err.status === 401 ? 'Invalid token' : 'Something went wrong');
      } else {
        setError("Can't reach server");
      }
      setConnecting(false);
    }
  }

  return (
    <ThemedView style={styles.container}>
      <KeyboardAvoidingView
        style={styles.flex}
        behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
        <SafeAreaView style={styles.safeArea}>
          <ThemedView style={styles.content}>
            <ThemedView style={styles.header}>
              <ThemedText type="title">Jarvis</ThemedText>
              <ThemedText themeColor="textSecondary" style={styles.explainer}>
                Paste your API token to connect.
              </ThemedText>
            </ThemedView>

            <ThemedView style={styles.form}>
              <TextInput
                value={value}
                onChangeText={(text) => {
                  setValue(text);
                  if (error) setError(null);
                }}
                placeholder="API token"
                placeholderTextColor={theme.textSecondary}
                autoCapitalize="none"
                autoCorrect={false}
                autoComplete="off"
                secureTextEntry={false}
                editable={!connecting}
                onSubmitEditing={handleConnect}
                returnKeyType="go"
                style={[
                  styles.input,
                  {
                    backgroundColor: theme.backgroundElement,
                    color: theme.text,
                    borderColor: error ? '#E5484D' : 'transparent',
                  },
                ]}
              />

              {error !== null && (
                <ThemedText type="small" style={styles.error}>
                  {error}
                </ThemedText>
              )}

              <Pressable
                onPress={handleConnect}
                disabled={!canSubmit}
                style={({ pressed }) => [
                  styles.button,
                  { opacity: !canSubmit ? 0.4 : pressed ? 0.8 : 1 },
                ]}>
                {connecting ? (
                  <ActivityIndicator color="#ffffff" />
                ) : (
                  <ThemedText style={styles.buttonLabel}>Connect</ThemedText>
                )}
              </Pressable>
            </ThemedView>
          </ThemedView>
        </SafeAreaView>
      </KeyboardAvoidingView>
    </ThemedView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  flex: {
    flex: 1,
  },
  safeArea: {
    flex: 1,
    alignItems: 'center',
  },
  content: {
    flex: 1,
    width: '100%',
    maxWidth: MaxContentWidth,
    justifyContent: 'center',
    paddingHorizontal: Spacing.four,
    gap: Spacing.five,
  },
  header: {
    gap: Spacing.two,
  },
  explainer: {
    textAlign: 'left',
  },
  form: {
    gap: Spacing.three,
  },
  input: {
    height: 52,
    borderRadius: Spacing.three,
    borderWidth: 1,
    paddingHorizontal: Spacing.three,
    fontSize: 16,
  },
  error: {
    color: '#E5484D',
  },
  button: {
    height: 52,
    borderRadius: Spacing.three,
    backgroundColor: ACCENT,
    alignItems: 'center',
    justifyContent: 'center',
  },
  buttonLabel: {
    color: '#ffffff',
    fontSize: 16,
    fontWeight: '600',
  },
});
