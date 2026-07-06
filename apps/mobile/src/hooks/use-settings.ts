import type { Settings } from '@jarvis/shared';
import { useQuery } from '@tanstack/react-query';

import { apiFetch } from '@/lib/api';

export type { Settings };

export function useSettings() {
  return useQuery({
    queryKey: ['settings'],
    queryFn: () => apiFetch<Settings>('/api/settings'),
  });
}
