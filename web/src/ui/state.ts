import { signal } from '@preact/signals';
import type { ReminderDraft } from '../core/models';
import { describeError } from '../app/errors';
import type { CaptureDraft } from '../app/pipeline';

export type Route =
  | { name: 'home' }
  | { name: 'memories'; query: string }
  | { name: 'memory'; id: string }
  | { name: 'similar'; id: string }
  | { name: 'reminders' }
  | { name: 'settings' }
  | { name: 'understanding' };

export function parseHash(hash: string): Route {
  const [path, queryString = ''] = hash.replace(/^#/, '').split('?');
  const parts = path.split('/').filter(Boolean);
  const params = new URLSearchParams(queryString);
  switch (parts[0]) {
    case 'memories':
      return { name: 'memories', query: params.get('q') ?? '' };
    case 'memory':
      return parts[1] ? { name: 'memory', id: parts[1] } : { name: 'home' };
    case 'similar':
      return parts[1] ? { name: 'similar', id: parts[1] } : { name: 'home' };
    case 'reminders':
      return { name: 'reminders' };
    case 'settings':
      return parts[1] === 'understanding' ? { name: 'understanding' } : { name: 'settings' };
    default:
      return { name: 'home' };
  }
}

export const route = signal<Route>(parseHash(location.hash));
const stack: string[] = [location.hash || '#/'];

window.addEventListener('hashchange', () => {
  const hash = location.hash || '#/';
  if (stack.length > 1 && stack[stack.length - 2] === hash) stack.pop();
  else stack.push(hash);
  route.value = parseHash(hash);
  window.scrollTo(0, 0);
});

export function navigate(path: string) {
  location.hash = path;
}

export function goBack() {
  if (stack.length > 1) history.back();
  else location.replace('#/');
}

export function goHome(path?: string) {
  stack.length = 0;
  stack.push('#/');
  location.replace('#/');
  if (path) setTimeout(() => navigate(path), 0);
}

export interface ReminderRequest {
  draft: ReminderDraft;
  memoryId?: string;
  memoryTitle?: string;
  body: string;
}

export type Sheet =
  | { type: 'voice' }
  | { type: 'text' }
  | { type: 'review'; draft: CaptureDraft }
  | { type: 'reminder'; request: ReminderRequest };

export const sheet = signal<Sheet | undefined>(undefined);
export const showLook = signal(false);
export const processing = signal<string | undefined>(undefined);

export interface AlertAction {
  label: string;
  role?: 'cancel' | 'destructive';
  run?: () => void;
}

export interface AlertState {
  title: string;
  message?: string;
  actions: AlertAction[];
  style: 'alert' | 'sheet';
}

export const alertState = signal<AlertState | undefined>(undefined);

export function showAlert(title: string, message?: string) {
  alertState.value = { title, message, actions: [{ label: 'OK', role: 'cancel' }], style: 'alert' };
}

export function showError(error: unknown) {
  showAlert('Something went wrong', describeError(error));
}

export function confirmDestructive(title: string, message: string, label: string): Promise<boolean> {
  return new Promise((resolve) => {
    alertState.value = {
      title,
      message,
      style: 'sheet',
      actions: [
        { label, role: 'destructive', run: () => resolve(true) },
        { label: 'Cancel', role: 'cancel', run: () => resolve(false) },
      ],
    };
  });
}
