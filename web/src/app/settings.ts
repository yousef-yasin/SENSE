import { effect, signal } from '@preact/signals';
import type { RemoteProviderConfiguration } from '../core/provider';

export type ProviderMode = 'onDevice' | 'openAICompatible';

function read(key: string): string | null {
  try {
    return localStorage.getItem(key);
  } catch {
    return null;
  }
}

function write(key: string, value: string | null) {
  try {
    if (value === null || value === '') localStorage.removeItem(key);
    else localStorage.setItem(key, value);
  } catch {
    // Storage can be unavailable in private browsing; settings then last for this session only.
  }
}

function persisted<T extends string>(key: string, fallback: T) {
  const value = signal<T>((read(key) as T | null) ?? fallback);
  effect(() => write(key, value.value));
  return value;
}

export const settings = {
  hasCompletedOnboarding: persisted<'yes' | 'no'>('settings.onboardingCompleted', 'no'),
  providerMode: persisted<ProviderMode>('settings.providerMode', 'onDevice'),
  providerBaseURL: persisted<string>('settings.providerBaseURL', ''),
  providerModel: persisted<string>('settings.providerModel', ''),
  apiKey: persisted<string>('provider.apiKey', ''),
};

export function remoteConfiguration(): RemoteProviderConfiguration | undefined {
  if (settings.providerMode.value !== 'openAICompatible') return undefined;
  const model = settings.providerModel.value.trim();
  const base = settings.providerBaseURL.value.trim();
  if (!model) return undefined;
  try {
    const url = new URL(base);
    if (url.protocol !== 'https:' && url.protocol !== 'http:') return undefined;
    if (!url.host) return undefined;
  } catch {
    return undefined;
  }
  const apiKey = settings.apiKey.value.trim();
  return apiKey ? { baseURL: base, model, apiKey } : { baseURL: base, model };
}

export function resetProvider() {
  settings.providerMode.value = 'onDevice';
  settings.providerBaseURL.value = '';
  settings.providerModel.value = '';
  settings.apiKey.value = '';
}
