import { signal } from '@preact/signals';

interface InstallPromptEvent extends Event {
  prompt(): Promise<void>;
  userChoice: Promise<{ outcome: 'accepted' | 'dismissed' }>;
}

export const installPrompt = signal<InstallPromptEvent | undefined>(undefined);

window.addEventListener('beforeinstallprompt', (event) => {
  event.preventDefault();
  installPrompt.value = event as InstallPromptEvent;
});

window.addEventListener('appinstalled', () => {
  installPrompt.value = undefined;
});

export function isStandalone(): boolean {
  return window.matchMedia('(display-mode: standalone)').matches || (navigator as { standalone?: boolean }).standalone === true;
}

export function isIOS(): boolean {
  return /iPad|iPhone|iPod/.test(navigator.userAgent) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
}

export async function promptInstall() {
  const event = installPrompt.value;
  if (!event) return;
  await event.prompt();
  await event.userChoice.catch(() => undefined);
  installPrompt.value = undefined;
}
