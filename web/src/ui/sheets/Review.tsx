import { useEffect, useMemo, useState } from 'preact/hooks';
import { BellPlus, Clock, MapPin, X } from 'lucide-preact';
import { MEMORY_KINDS, type MemoryKind, reminderSuggestions } from '../../core/models';
import type { CaptureDraft } from '../../app/pipeline';
import { requestNotificationPermission } from '../../app/reminders';
import { createReminder, saveMemory, similarToDraft } from '../../app/store';
import { EntityRow, Group, HighlightRow, MemoryRow, Sheet, SheetBar } from '../components';
import { formatDateTime, fromLocalInput, kindInfo, nextHour, originInfo, toLocalInput } from '../presentation';
import { type ReminderRequest, navigate, sheet, showError } from '../state';

interface Spec {
  id: string;
  title: string;
  fireAt: Date;
}

interface Suggestion extends Spec {
  dueDate?: Date;
  on: boolean;
}

export function ReviewSheet({ draft }: { draft: CaptureDraft }) {
  const understanding = draft.understanding;
  const [title, setTitle] = useState(understanding.title);
  const [kind, setKind] = useState<MemoryKind>(understanding.kind);
  const [suggestions, setSuggestions] = useState<Suggestion[]>(() =>
    reminderSuggestions(understanding).flatMap((s) =>
      s.timing.type === 'at' ? [{ id: crypto.randomUUID(), title: s.title, fireAt: s.timing.date, dueDate: s.dueDate, on: false }] : [],
    ),
  );
  const [extras, setExtras] = useState<Spec[]>([]);
  const [composer, setComposer] = useState<ReminderRequest>();
  const [saving, setSaving] = useState(false);
  const [showText, setShowText] = useState(false);
  const imageURL = useMemo(() => (draft.image ? URL.createObjectURL(draft.image) : undefined), [draft.image]);
  const similar = useMemo(() => similarToDraft(draft), [draft]);
  const details = understanding.entities.filter((e) => e.kind !== 'date' && e.kind !== 'label');
  const OriginIcon = originInfo[understanding.origin].icon;

  useEffect(() => () => imageURL && URL.revokeObjectURL(imageURL), [imageURL]);

  const update = (id: string, change: Partial<Suggestion>) => setSuggestions((list) => list.map((s) => (s.id === id ? { ...s, ...change } : s)));

  const save = async () => {
    const specs = [...suggestions.filter((s) => s.on), ...extras];
    if (specs.length > 0) await requestNotificationPermission();
    setSaving(true);
    try {
      const memory = await saveMemory(draft, title, kind);
      let failure: unknown;
      for (const spec of specs) {
        try {
          await createReminder({ title: spec.title, body: memory.summary, fireAt: spec.fireAt, memoryId: memory.id });
        } catch (error) {
          failure ??= error;
        }
      }
      sheet.value = undefined;
      navigate(`#/memory/${memory.id}`);
      if (failure) showError(failure);
    } catch (error) {
      showError(error);
    } finally {
      setSaving(false);
    }
  };

  return (
    <Sheet onClose={() => !saving && (sheet.value = undefined)} dismissable={!saving}>
      <SheetBar
        title="Review"
        leading={
          <button class="nav-button destructive" onClick={() => (sheet.value = undefined)} disabled={saving}>
            Discard
          </button>
        }
        trailing={
          <button class="nav-button strong" onClick={save} disabled={saving}>
            {saving ? 'Saving…' : 'Save'}
          </button>
        }
      />
      <div class="sheet-scroll grouped">
        {imageURL && <img class="hero-image" src={imageURL} alt="Captured image" />}

        <Group
          footer={
            <span class="inline-icon">
              <OriginIcon size={13} aria-hidden="true" /> {originInfo[understanding.origin].title}
            </span>
          }
        >
          <div class="row">
            <textarea class="title-input" rows={2} value={title} placeholder={kindInfo[kind].title} onInput={(e) => setTitle((e.target as HTMLTextAreaElement).value)} aria-label="Title" />
          </div>
          <label class="row picker-row">
            <span>Type</span>
            <select value={kind} onChange={(e) => setKind((e.target as HTMLSelectElement).value as MemoryKind)}>
              {MEMORY_KINDS.map((k) => (
                <option value={k}>{kindInfo[k].title}</option>
              ))}
            </select>
          </label>
        </Group>

        {understanding.summary && (
          <Group header="Summary">
            <div class="row">{understanding.summary}</div>
          </Group>
        )}

        {understanding.highlights.length > 0 && (
          <Group header="What matters">
            {understanding.highlights.map((h) => (
              <HighlightRow highlight={h} />
            ))}
          </Group>
        )}

        <Group header={suggestions.length > 0 ? 'Suggested reminders' : 'Reminders'}>
          {suggestions.map((s) => (
            <div class="row suggestion">
              <label class="toggle-row">
                <div class="grow">
                  <div>{s.title}</div>
                  {s.dueDate && <div class="caption secondary">Due {formatDateTime(s.dueDate)}</div>}
                </div>
                <input type="checkbox" class="switch" checked={s.on} onChange={(e) => update(s.id, { on: (e.target as HTMLInputElement).checked })} />
              </label>
              {s.on && (
                <label class="picker-row compact">
                  <span>Remind me</span>
                  <input
                    type="datetime-local"
                    value={toLocalInput(s.fireAt)}
                    min={toLocalInput(new Date())}
                    onChange={(e) => {
                      const date = fromLocalInput((e.target as HTMLInputElement).value);
                      if (date) update(s.id, { fireAt: date });
                    }}
                  />
                </label>
              )}
            </div>
          ))}
          {extras.map((spec) => (
            <div class="row icon-row">
              <Clock size={20} class="tint" aria-hidden="true" />
              <div class="grow">
                <div>{spec.title}</div>
                <div class="caption secondary">{formatDateTime(spec.fireAt)}</div>
              </div>
              <button class="icon-button small" onClick={() => setExtras((list) => list.filter((e) => e.id !== spec.id))} aria-label="Remove reminder">
                <X size={18} />
              </button>
            </div>
          ))}
          <button
            class="row button-row icon-row tint"
            onClick={() =>
              setComposer({
                draft: { title: title || kindInfo[kind].title, timing: { type: 'unspecified' }, refersToContext: false },
                body: understanding.summary,
              })
            }
          >
            <BellPlus size={20} aria-hidden="true" /> Add a reminder…
          </button>
        </Group>

        {details.length > 0 && (
          <Group header="Details">
            {details.map((e) => (
              <EntityRow entity={e} />
            ))}
          </Group>
        )}

        {similar.length > 0 && (
          <Group header="You've captured something similar">
            {similar.map((memory) => (
              <div class="row">
                <MemoryRow memory={memory} />
              </div>
            ))}
          </Group>
        )}

        {draft.input.text && (
          <Group>
            <button class="row button-row disclosure" onClick={() => setShowText(!showText)} aria-expanded={showText}>
              Captured text <span class={`chevron ${showText ? 'open' : ''}`}>›</span>
            </button>
            {showText && <pre class="row captured-text">{draft.input.text}</pre>}
          </Group>
        )}
      </div>

      {composer && (
        <ReminderComposer
          request={composer}
          onClose={() => setComposer(undefined)}
          onSubmit={async (spec) => setExtras((list) => [...list, { id: crypto.randomUUID(), ...spec }])}
        />
      )}
    </Sheet>
  );
}

export function ReminderComposer(props: { request: ReminderRequest; onClose: () => void; onSubmit: (spec: { title: string; fireAt: Date }) => Promise<void> }) {
  const { draft } = props.request;
  const [title, setTitle] = useState(draft.title);
  const [when, setWhen] = useState(() => toLocalInput(draft.timing.type === 'at' ? new Date(Math.max(draft.timing.date.getTime(), Date.now() + 60_000)) : nextHour()));
  const [submitting, setSubmitting] = useState(false);
  const place = draft.timing.type === 'arriving' || draft.timing.type === 'leaving' ? draft.timing.place : undefined;
  const fireAt = fromLocalInput(when);
  const canSubmit = title.trim().length > 0 && fireAt !== undefined && fireAt.getTime() > Date.now() && !submitting;

  const submit = async () => {
    if (!fireAt || !canSubmit) return;
    setSubmitting(true);
    try {
      await props.onSubmit({ title: title.trim(), fireAt });
      props.onClose();
    } catch (error) {
      showError(error);
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <Sheet onClose={props.onClose}>
      <SheetBar
        title="Reminder"
        leading={
          <button class="nav-button" onClick={props.onClose}>
            Cancel
          </button>
        }
        trailing={
          <button class="nav-button strong" onClick={submit} disabled={!canSubmit}>
            Add
          </button>
        }
      />
      <div class="sheet-scroll grouped">
        <Group footer={props.request.memoryTitle ? `About “${props.request.memoryTitle}”` : undefined}>
          <div class="row">
            <textarea class="plain-input" rows={2} value={title} placeholder="What should SENSE remind you about?" onInput={(e) => setTitle((e.target as HTMLTextAreaElement).value)} />
          </div>
        </Group>
        {place && (
          <Group>
            <div class="row icon-row notice">
              <MapPin size={20} color="var(--orange)" aria-hidden="true" />
              <div class="small">
                Reminders for when you arrive at or leave a place (“{place}”) need the SENSE iPhone app, because browsers can't watch your location in the background. Pick a time instead.
              </div>
            </div>
          </Group>
        )}
        <Group header="When">
          <label class="row picker-row">
            <span>Date & time</span>
            <input type="datetime-local" value={when} min={toLocalInput(new Date())} onInput={(e) => setWhen((e.target as HTMLInputElement).value)} />
          </label>
        </Group>
      </div>
    </Sheet>
  );
}

export function ReminderSheet({ request }: { request: ReminderRequest }) {
  return (
    <ReminderComposer
      request={request}
      onClose={() => (sheet.value = undefined)}
      onSubmit={async (spec) => {
        await requestNotificationPermission();
        await createReminder({ title: spec.title, body: request.body, fireAt: spec.fireAt, memoryId: request.memoryId });
      }}
    />
  );
}
