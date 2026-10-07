import { useEffect, useState } from 'preact/hooks';
import { BellPlus, CalendarPlus, Copy, SquareDashed, Trash2 } from 'lucide-preact';
import { MEMORY_KINDS, type MemoryKind } from '../../core/models';
import { addToCalendar } from '../../app/reminders';
import { deleteMemory, deleteReminder, imageURL, memoryByID, reminders, updateMemory } from '../../app/store';
import { EmptyState, EntityRow, Group, HighlightRow, NavBar, ReminderRow, displayTitle } from '../components';
import { formatDateTime, kindInfo, sourceInfo } from '../presentation';
import { confirmDestructive, goBack, navigate, sheet, showError } from '../state';

export function MemoryDetail({ id }: { id: string }) {
  const memory = memoryByID(id);
  const [image, setImage] = useState<string>();
  const [editing, setEditing] = useState(false);
  const [title, setTitle] = useState('');
  const [kind, setKind] = useState<MemoryKind>('note');
  const [showText, setShowText] = useState(false);

  useEffect(() => {
    if (memory?.imageId) imageURL(memory.imageId).then(setImage);
  }, [memory?.imageId]);

  if (!memory) {
    return (
      <div class="screen">
        <NavBar title="" back />
        <EmptyState icon={<SquareDashed size={48} />} title="Memory Not Found" message="It may have been deleted." />
      </div>
    );
  }

  const linked = reminders.value.filter((r) => r.memoryId === memory.id).sort((a, b) => a.fireAt.getTime() - b.fireAt.getTime());
  const details = memory.entities.filter((e) => e.kind !== 'label');
  const info = kindInfo[memory.kind];
  const SourceIcon = sourceInfo[memory.source].icon;

  const saveEdits = async () => {
    try {
      await updateMemory(memory.id, title, kind);
      setEditing(false);
    } catch (error) {
      showError(error);
    }
  };

  const remove = async () => {
    if (!(await confirmDestructive('Delete this memory?', 'Its photo and reminders are removed too.', 'Delete Memory'))) return;
    try {
      await deleteMemory(memory.id);
      goBack();
    } catch (error) {
      showError(error);
    }
  };

  const removeReminder = async (reminderId: string) => {
    if (!(await confirmDestructive('Delete this reminder?', '', 'Delete'))) return;
    await deleteReminder(reminderId).catch(showError);
  };

  return (
    <div class="screen">
      <NavBar
        title=""
        back
        trailing={
          editing ? (
            <button class="nav-button strong" onClick={saveEdits}>
              Done
            </button>
          ) : (
            <button
              class="nav-button"
              onClick={() => {
                setTitle(memory.title);
                setKind(memory.kind);
                setEditing(true);
              }}
            >
              Edit
            </button>
          )
        }
      />
      <div class="grouped">
        {image && <img class="hero-image" src={image} alt="Captured image" />}

        <Group
          footer={
            <span class="inline-icon">
              <SourceIcon size={13} aria-hidden="true" /> {formatDateTime(memory.createdAt)}
            </span>
          }
        >
          {editing ? (
            <>
              <div class="row">
                <textarea class="title-input" rows={2} value={title} placeholder="Title" onInput={(e) => setTitle((e.target as HTMLTextAreaElement).value)} />
              </div>
              <label class="row picker-row">
                <span>Type</span>
                <select value={kind} onChange={(e) => setKind((e.target as HTMLSelectElement).value as MemoryKind)}>
                  {MEMORY_KINDS.map((k) => (
                    <option value={k}>{kindInfo[k].title}</option>
                  ))}
                </select>
              </label>
            </>
          ) : (
            <div class="row detail-header">
              <div class="caption strong inline-icon" style={{ color: info.tint }}>
                <info.icon size={14} aria-hidden="true" /> {info.title}
              </div>
              <div class="detail-title">{displayTitle(memory)}</div>
              {memory.summary && <div class="secondary">{memory.summary}</div>}
            </div>
          )}
        </Group>

        {memory.highlights.length > 0 && (
          <Group header="What matters">
            {memory.highlights.map((h) => (
              <HighlightRow highlight={h} />
            ))}
          </Group>
        )}

        {details.length > 0 && (
          <Group header="Details">
            {details.map((e) => (
              <EntityRow entity={e} />
            ))}
          </Group>
        )}

        <Group header="Reminders">
          {linked.map((reminder) => (
            <div class={`row reminder-line ${reminder.delivered ? 'done' : ''}`}>
              <ReminderRow reminder={reminder} />
              <div class="row-actions">
                {!reminder.delivered && (
                  <button class="icon-button small" onClick={() => addToCalendar(reminder)} aria-label="Add to Calendar">
                    <CalendarPlus size={18} />
                  </button>
                )}
                <button class="icon-button small destructive" onClick={() => removeReminder(reminder.id)} aria-label="Delete reminder">
                  <Trash2 size={18} />
                </button>
              </div>
            </div>
          ))}
          <button
            class="row button-row icon-row tint"
            onClick={() =>
              (sheet.value = {
                type: 'reminder',
                request: {
                  draft: { title: displayTitle(memory), timing: { type: 'unspecified' }, refersToContext: false },
                  memoryId: memory.id,
                  memoryTitle: displayTitle(memory),
                  body: memory.summary,
                },
              })
            }
          >
            <BellPlus size={20} aria-hidden="true" /> Remind me…
          </button>
        </Group>

        {memory.placeName && (
          <Group header="Where">
            <div class="row">{memory.placeName}</div>
          </Group>
        )}

        {memory.tags.length > 0 && (
          <Group header="Tags">
            <div class="row secondary">{memory.tags.join(' · ')}</div>
          </Group>
        )}

        {memory.content && (
          <Group>
            <button class="row button-row disclosure" onClick={() => setShowText(!showText)} aria-expanded={showText}>
              Captured text <span class={`chevron ${showText ? 'open' : ''}`}>›</span>
            </button>
            {showText && <pre class="row captured-text">{memory.content}</pre>}
          </Group>
        )}

        <Group>
          <button class="row button-row icon-row tint" onClick={() => navigate(`#/similar/${memory.id}`)}>
            <Copy size={20} aria-hidden="true" /> Have I seen this before?
          </button>
          <button class="row button-row icon-row destructive" onClick={remove}>
            <Trash2 size={20} aria-hidden="true" /> Delete Memory
          </button>
        </Group>
      </div>
    </div>
  );
}
