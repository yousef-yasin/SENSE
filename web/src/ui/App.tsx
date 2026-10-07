import { useEffect } from 'preact/hooks';
import { BellRing, X } from 'lucide-preact';
import { dismissDue, dueReminders } from '../app/reminders';
import { settings } from '../app/settings';
import { storageError, storageReady } from '../app/store';
import { captureFile, registerFileInput } from './actions';
import { AlertHost, ProcessingOverlay } from './components';
import { formatDateTime } from './presentation';
import { Home, Onboarding } from './screens/Home';
import { Memories, SimilarMemories } from './screens/Memories';
import { MemoryDetail } from './screens/MemoryDetail';
import { Reminders } from './screens/Reminders';
import { Settings } from './screens/Settings';
import { Understanding } from './screens/Understanding';
import { LiveLook, TextSheet, VoiceSheet } from './sheets/Capture';
import { ReminderSheet, ReviewSheet } from './sheets/Review';
import { navigate, route, sheet, showAlert, showLook } from './state';

function Screen() {
  const current = route.value;
  switch (current.name) {
    case 'home':
      return <Home />;
    case 'memories':
      return <Memories initialQuery={current.query} />;
    case 'memory':
      return <MemoryDetail id={current.id} />;
    case 'similar':
      return <SimilarMemories id={current.id} />;
    case 'reminders':
      return <Reminders />;
    case 'settings':
      return <Settings />;
    case 'understanding':
      return <Understanding />;
  }
}

function SheetHost() {
  const current = sheet.value;
  if (!current) return null;
  switch (current.type) {
    case 'voice':
      return <VoiceSheet />;
    case 'text':
      return <TextSheet />;
    case 'review':
      return <ReviewSheet key={current.draft.id} draft={current.draft} />;
    case 'reminder':
      return <ReminderSheet request={current.request} />;
  }
}

function DueBanners() {
  const due = dueReminders.value;
  if (due.length === 0) return null;
  return (
    <div class="banners" aria-live="assertive">
      {due.map((reminder) => (
        <div class="banner">
          <button
            class="banner-main"
            onClick={() => {
              dismissDue(reminder.id);
              navigate(reminder.memoryId ? `#/memory/${reminder.memoryId}` : '#/reminders');
            }}
          >
            <BellRing size={22} class="tint" aria-hidden="true" />
            <div>
              <div class="strong">{reminder.title}</div>
              <div class="caption secondary">{reminder.body || formatDateTime(reminder.fireAt)}</div>
            </div>
          </button>
          <button class="icon-button small" onClick={() => dismissDue(reminder.id)} aria-label="Dismiss">
            <X size={18} />
          </button>
        </div>
      ))}
    </div>
  );
}

export function App() {
  useEffect(() => {
    if (storageError.value) showAlert('Storage unavailable', storageError.value.message);
  }, [storageError.value]);

  if (!storageReady.value) return <div class="launch" />;

  return (
    <>
      {settings.hasCompletedOnboarding.value === 'yes' ? (
        <div class="page" key={JSON.stringify(route.value)}>
          <Screen />
        </div>
      ) : (
        <Onboarding />
      )}
      <input
        ref={registerFileInput}
        type="file"
        accept="image/*"
        class="hidden-input"
        onChange={(e) => {
          const file = (e.target as HTMLInputElement).files?.[0];
          if (file) captureFile(file);
        }}
      />
      <SheetHost />
      {showLook.value && <LiveLook />}
      <DueBanners />
      <ProcessingOverlay />
      <AlertHost />
    </>
  );
}
