import { Brain, Camera, ChevronRight, Layers, LockKeyhole, Mic, ScanLine, Settings, Sparkles, TextCursor } from 'lucide-preact';
import { memories, openReminders } from '../../app/store';
import { settings } from '../../app/settings';
import { chooseImage, startLook, startVoice } from '../actions';
import { MemoryRow, ReminderRow } from '../components';
import { navigate, sheet } from '../state';

function CaptureTile(props: { title: string; icon: typeof Camera; tint: string; badge?: number; hint: string; onClick: () => void }) {
  const Icon = props.icon;
  return (
    <button class="tile" onClick={props.onClick} aria-label={`${props.title}. ${props.hint}`}>
      <div class="tile-top">
        <Icon size={26} color={props.tint} aria-hidden="true" />
        {props.badge !== undefined && <span class="tile-badge">{props.badge}</span>}
      </div>
      <div class="tile-title">{props.title}</div>
    </button>
  );
}

function SectionHeader(props: { title: string; action?: string; onAction?: () => void }) {
  return (
    <div class="section-header">
      <h2>{props.title}</h2>
      {props.action && (
        <button class="text-button" onClick={props.onAction}>
          {props.action}
        </button>
      )}
    </div>
  );
}

export function Home() {
  const all = memories.value;
  const upcoming = openReminders.value.slice(0, 3);

  return (
    <div class="screen home">
      <header class="home-toolbar">
        <button class="icon-button" onClick={() => navigate('#/settings')} aria-label="Settings">
          <Settings size={24} />
        </button>
      </header>
      <div class="home-content">
        <div class="home-header">
          <h1 class="wordmark">SENSE</h1>
          <p class="secondary">Capture something. SENSE understands it.</p>
        </div>

        <button class="look-card" onClick={startLook} aria-label="What's important here? Opens the camera and explains what it sees.">
          <div class="look-icon" aria-hidden="true">
            <ScanLine size={30} strokeWidth={2.2} />
          </div>
          <div class="look-text">
            <div class="look-title">What's important here?</div>
            <div class="look-subtitle">Point your camera at a sign, document or object.</div>
          </div>
          <ChevronRight size={22} aria-hidden="true" class="look-chevron" />
        </button>

        <div class="tile-grid">
          <CaptureTile title="Camera" icon={Camera} tint="var(--blue)" hint="Take a photo or choose one to understand." onClick={chooseImage} />
          <CaptureTile title="Voice" icon={Mic} tint="var(--orange)" hint="Speak a note, a reminder or a question." onClick={startVoice} />
          <CaptureTile title="Text" icon={TextCursor} tint="var(--purple)" hint="Type a note, a reminder or a question." onClick={() => (sheet.value = { type: 'text' })} />
          <CaptureTile
            title="Memories"
            icon={Layers}
            tint="var(--green)"
            badge={all.length > 0 ? all.length : undefined}
            hint="Browse and search what you've captured."
            onClick={() => navigate('#/memories')}
          />
        </div>

        {upcoming.length > 0 && (
          <section>
            <SectionHeader title="Upcoming" action="See All" onAction={() => navigate('#/reminders')} />
            <div class="card list-card">
              {upcoming.map((reminder) => (
                <button class="card-row" onClick={() => navigate(reminder.memoryId ? `#/memory/${reminder.memoryId}` : '#/reminders')}>
                  <ReminderRow reminder={reminder} />
                </button>
              ))}
            </div>
          </section>
        )}

        <section>
          <SectionHeader title="Recent" action={all.length > 0 ? 'See All' : undefined} onAction={() => navigate('#/memories')} />
          {all.length === 0 ? (
            <div class="card padded">
              <div class="headline">Nothing captured yet</div>
              <p class="secondary small">Try photographing a poster, a receipt or a document, or say “Remind me to call the lab tomorrow at 5.”</p>
            </div>
          ) : (
            <div class="card list-card">
              {all.slice(0, 5).map((memory) => (
                <button class="card-row" onClick={() => navigate(`#/memory/${memory.id}`)}>
                  <MemoryRow memory={memory} />
                </button>
              ))}
            </div>
          )}
        </section>
      </div>
    </div>
  );
}

export function Onboarding() {
  const features = [
    { icon: ScanLine, title: 'Capture anything', detail: 'Point your camera, pick a photo, speak, or type. No folders, no tagging.' },
    { icon: Sparkles, title: 'SENSE understands it', detail: 'Deadlines, dates, amounts, warnings and requirements are pulled out for you, with reminders one tap away.' },
    { icon: Brain, title: 'Remember and recall', detail: 'Ask things like “What did I capture yesterday?” and find it again.' },
    {
      icon: LockKeyhole,
      title: 'Private by design',
      detail: 'Text recognition, understanding and search run in this browser, and your memories are stored only on this device. SENSE asks before using the camera or microphone. Nothing is sent anywhere unless you connect your own AI provider.',
    },
  ];
  return (
    <div class="onboarding">
      <div class="onboarding-content">
        <h1 class="wordmark">SENSE</h1>
        <p class="onboarding-tagline">AI that understands the world around you.</p>
        <div class="features">
          {features.map(({ icon: Icon, title, detail }) => (
            <div class="feature">
              <Icon size={28} class="tint" aria-hidden="true" />
              <div>
                <div class="headline">{title}</div>
                <div class="secondary small">{detail}</div>
              </div>
            </div>
          ))}
        </div>
      </div>
      <div class="onboarding-footer">
        <button class="primary-button" onClick={() => (settings.hasCompletedOnboarding.value = 'yes')}>
          Get Started
        </button>
      </div>
    </div>
  );
}
