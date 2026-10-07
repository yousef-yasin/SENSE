import type { ComponentChildren } from 'preact';
import { useEffect, useState } from 'preact/hooks';
import { Banknote, Bell, Building2, Calendar, ChevronLeft, Link, Mail, Phone, Tag } from 'lucide-preact';
import type { ExtractedEntity, Highlight } from '../core/models';
import type { MemoryRecord, ReminderRecord } from '../app/db';
import { imageURL } from '../app/store';
import { formatDateTime, formatRelative, highlightInfo, kindInfo } from './presentation';
import { alertState, goBack, processing } from './state';

export function displayTitle(memory: MemoryRecord): string {
  return memory.title || kindInfo[memory.kind].title;
}

export function NavBar(props: { title: string; large?: boolean; back?: boolean; backLabel?: string; trailing?: ComponentChildren }) {
  return (
    <header class={`navbar ${props.large ? 'navbar-large' : ''}`}>
      <div class="navbar-bar">
        <div class="navbar-leading">
          {props.back && (
            <button class="nav-button" onClick={goBack} aria-label="Back">
              <ChevronLeft size={26} strokeWidth={2.4} />
              <span>{props.backLabel ?? 'Back'}</span>
            </button>
          )}
        </div>
        {!props.large && <h1 class="navbar-title">{props.title}</h1>}
        <div class="navbar-trailing">{props.trailing}</div>
      </div>
      {props.large && <h1 class="large-title">{props.title}</h1>}
    </header>
  );
}

export function Group(props: { header?: ComponentChildren; footer?: ComponentChildren; children: ComponentChildren; plain?: boolean }) {
  return (
    <section class="group">
      {props.header && <h2 class="group-header">{props.header}</h2>}
      <div class={props.plain ? 'group-plain' : 'group-body'}>{props.children}</div>
      {props.footer && <p class="group-footer">{props.footer}</p>}
    </section>
  );
}

export function MemoryThumbnail({ memory, size = 52 }: { memory: MemoryRecord; size?: number }) {
  const [url, setURL] = useState<string>();
  useEffect(() => {
    let active = true;
    if (memory.imageId) imageURL(memory.imageId).then((value) => active && setURL(value));
    return () => {
      active = false;
    };
  }, [memory.imageId]);
  const info = kindInfo[memory.kind];
  const Icon = info.icon;
  return (
    <div class="thumb" style={{ width: size, height: size, color: info.tint }} aria-hidden="true">
      <div class="thumb-fill" style={{ background: info.tint }} />
      {url ? <img src={url} alt="" /> : <Icon size={size * 0.42} />}
    </div>
  );
}

export function MemoryRow({ memory }: { memory: MemoryRecord }) {
  return (
    <div class="memory-row">
      <MemoryThumbnail memory={memory} />
      <div class="memory-row-text">
        <div class="memory-row-title">{displayTitle(memory)}</div>
        {memory.summary && <div class="memory-row-summary">{memory.summary}</div>}
        <div class="memory-row-meta">
          {kindInfo[memory.kind].title} · {formatRelative(memory.createdAt)}
          {memory.placeName ? ` · ${memory.placeName}` : ''}
        </div>
      </div>
    </div>
  );
}

export function ReminderRow({ reminder }: { reminder: ReminderRecord }) {
  return (
    <div class="reminder-row">
      <Bell size={20} class="tint" aria-hidden="true" />
      <div class="reminder-row-text">
        <div class="reminder-row-title">{reminder.title}</div>
        <div class="caption">{formatDateTime(reminder.fireAt)}</div>
      </div>
    </div>
  );
}

export function HighlightRow({ highlight }: { highlight: Highlight }) {
  const info = highlightInfo[highlight.kind];
  const Icon = info.icon;
  return (
    <div class="row icon-row">
      <Icon size={20} color={info.tint} aria-hidden="true" />
      <div>
        <div class="caption strong" style={{ color: info.tint }}>
          {info.title}
        </div>
        <div>{highlight.text}</div>
      </div>
    </div>
  );
}

export function EntityRow({ entity }: { entity: ExtractedEntity }) {
  const link = (href: string, Icon: typeof Phone) => (
    <a class="row icon-row link" href={href} target={href.startsWith('http') ? '_blank' : undefined} rel="noopener noreferrer">
      <Icon size={20} aria-hidden="true" />
      <span class="truncate">{entity.text}</span>
    </a>
  );
  const plain = (Icon: typeof Phone) => (
    <div class="row icon-row">
      <Icon size={20} class="tint" aria-hidden="true" />
      <span>{entity.text}</span>
    </div>
  );
  switch (entity.kind) {
    case 'phone':
      return link(`tel:${entity.value}`, Phone);
    case 'email':
      return link(`mailto:${entity.value}`, Mail);
    case 'link':
      return link(entity.value, Link);
    case 'money':
      return plain(Banknote);
    case 'merchant':
      return plain(Building2);
    case 'date':
      return plain(Calendar);
    case 'label':
      return plain(Tag);
  }
}

export function Sheet(props: { onClose: () => void; children: ComponentChildren; medium?: boolean; dismissable?: boolean }) {
  useEffect(() => {
    document.body.classList.add('sheet-open');
    return () => document.body.classList.remove('sheet-open');
  }, []);
  return (
    <div class="sheet-layer" role="dialog" aria-modal="true">
      <div class="sheet-backdrop" onClick={() => props.dismissable !== false && props.onClose()} />
      <div class={`sheet ${props.medium ? 'sheet-medium' : ''}`}>{props.children}</div>
    </div>
  );
}

export function SheetBar(props: { title: string; leading?: ComponentChildren; trailing?: ComponentChildren }) {
  return (
    <div class="sheet-bar">
      <div class="navbar-leading">{props.leading}</div>
      <h1 class="navbar-title">{props.title}</h1>
      <div class="navbar-trailing">{props.trailing}</div>
    </div>
  );
}

export function ProcessingOverlay() {
  const message = processing.value;
  if (!message) return null;
  return (
    <div class="processing-layer" role="status" aria-live="polite">
      <div class="processing">
        <div class="spinner" />
        <div class="processing-message">{message}</div>
      </div>
    </div>
  );
}

export function AlertHost() {
  const state = alertState.value;
  if (!state) return null;
  const close = (run?: () => void) => {
    alertState.value = undefined;
    run?.();
  };
  const cancel = state.actions.find((a) => a.role === 'cancel');
  if (state.style === 'sheet') {
    return (
      <div class="alert-layer" role="alertdialog" aria-modal="true">
        <div class="sheet-backdrop" onClick={() => close(cancel?.run)} />
        <div class="action-sheet">
          <div class="action-group">
            <div class="action-heading">
              <div class="action-title">{state.title}</div>
              {state.message && <div class="action-message">{state.message}</div>}
            </div>
            {state.actions
              .filter((a) => a.role !== 'cancel')
              .map((action) => (
                <button class={`action-button ${action.role === 'destructive' ? 'destructive' : ''}`} onClick={() => close(action.run)}>
                  {action.label}
                </button>
              ))}
          </div>
          {cancel && (
            <button class="action-button action-cancel" onClick={() => close(cancel.run)}>
              {cancel.label}
            </button>
          )}
        </div>
      </div>
    );
  }
  return (
    <div class="alert-layer centered" role="alertdialog" aria-modal="true">
      <div class="sheet-backdrop" />
      <div class="alert">
        <div class="alert-text">
          <div class="alert-title">{state.title}</div>
          {state.message && <div class="alert-message">{state.message}</div>}
        </div>
        <div class="alert-buttons">
          {state.actions.map((action) => (
            <button class={`alert-button ${action.role === 'cancel' ? 'strong' : ''} ${action.role === 'destructive' ? 'destructive' : ''}`} onClick={() => close(action.run)}>
              {action.label}
            </button>
          ))}
        </div>
      </div>
    </div>
  );
}

export function EmptyState(props: { icon: ComponentChildren; title: string; message?: string }) {
  return (
    <div class="empty-state">
      <div class="empty-icon">{props.icon}</div>
      <div class="empty-title">{props.title}</div>
      {props.message && <div class="empty-message">{props.message}</div>}
    </div>
  );
}
