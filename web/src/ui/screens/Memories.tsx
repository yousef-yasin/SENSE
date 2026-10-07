import { useEffect, useMemo, useState } from 'preact/hooks';
import { CopyX, Filter, Layers, Search, Trash2, X } from 'lucide-preact';
import { MEMORY_KINDS, type MemoryKind } from '../../core/models';
import type { MemoryRecord } from '../../app/db';
import { deleteMemory, memories, memoryByID, search, similarTo } from '../../app/store';
import { EmptyState, Group, MemoryRow, NavBar } from '../components';
import { kindInfo } from '../presentation';
import { confirmDestructive, navigate, showError } from '../state';

export function Memories({ initialQuery }: { initialQuery: string }) {
  const [query, setQuery] = useState(initialQuery);
  const [kindFilter, setKindFilter] = useState<MemoryKind | ''>('');
  const [results, setResults] = useState<MemoryRecord[] | undefined>();
  const trimmed = query.trim();
  const all = memories.value;

  useEffect(() => setQuery(initialQuery), [initialQuery]);

  useEffect(() => {
    if (!trimmed) {
      setResults(undefined);
      return;
    }
    const timer = setTimeout(() => setResults(search(trimmed)), 250);
    return () => clearTimeout(timer);
  }, [trimmed, all]);

  const visible = useMemo(() => {
    const base = trimmed ? (results ?? []) : all;
    return kindFilter ? base.filter((m) => m.kind === kindFilter) : base;
  }, [trimmed, results, all, kindFilter]);

  const remove = async (memory: MemoryRecord) => {
    if (!(await confirmDestructive('Delete this memory?', 'Its photo and reminders are removed too.', 'Delete'))) return;
    try {
      await deleteMemory(memory.id);
    } catch (error) {
      showError(error);
    }
  };

  return (
    <div class="screen">
      <NavBar
        title="Memories"
        large
        back
        backLabel="SENSE"
        trailing={
          <label class="icon-button select-wrap" aria-label="Filter by type">
            <Filter size={22} fill={kindFilter ? 'currentColor' : 'none'} />
            <select value={kindFilter} onChange={(e) => setKindFilter((e.target as HTMLSelectElement).value as MemoryKind | '')}>
              <option value="">All Types</option>
              {MEMORY_KINDS.map((kind) => (
                <option value={kind}>{kindInfo[kind].title}</option>
              ))}
            </select>
          </label>
        }
      />
      <div class="search-field">
        <Search size={17} aria-hidden="true" />
        <input type="search" placeholder="Ask about what you've captured" value={query} onInput={(e) => setQuery((e.target as HTMLInputElement).value)} enterKeyHint="search" />
        {query && (
          <button class="clear-button" onClick={() => setQuery('')} aria-label="Clear search">
            <X size={14} />
          </button>
        )}
      </div>

      {all.length === 0 ? (
        <EmptyState icon={<Layers size={48} />} title="No Memories Yet" message="Things you capture with the camera, your voice or text appear here." />
      ) : trimmed && results !== undefined && visible.length === 0 ? (
        <EmptyState icon={<Search size={48} />} title={`No Results for “${trimmed}”`} message="Check the spelling or try a new search." />
      ) : !trimmed && visible.length === 0 && kindFilter ? (
        <EmptyState icon={<Filter size={48} />} title={`No ${kindInfo[kindFilter].title} Memories`} />
      ) : (
        <div class="plain-list">
          {visible.map((memory) => (
            <div class="plain-list-row">
              <button class="plain-list-main" onClick={() => navigate(`#/memory/${memory.id}`)}>
                <MemoryRow memory={memory} />
              </button>
              <button class="row-delete" onClick={() => remove(memory)} aria-label={`Delete ${memory.title || kindInfo[memory.kind].title}`}>
                <Trash2 size={18} />
              </button>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

export function SimilarMemories({ id }: { id: string }) {
  const source = memoryByID(id);
  const matches = source ? similarTo(source) : [];
  return (
    <div class="screen">
      <NavBar title="Have I Seen This?" back />
      <div class="grouped">
        {source && (
          <Group header="Comparing">
            <button class="row button-row" onClick={() => navigate(`#/memory/${source.id}`)}>
              <MemoryRow memory={source} />
            </button>
          </Group>
        )}
        {matches.length > 0 ? (
          <Group header="Seen before">
            {matches.map((memory) => (
              <button class="row button-row" onClick={() => navigate(`#/memory/${memory.id}`)}>
                <MemoryRow memory={memory} />
              </button>
            ))}
          </Group>
        ) : (
          <EmptyState icon={<CopyX size={48} />} title="Nothing Similar" message="You haven't captured anything like this before." />
        )}
      </div>
    </div>
  );
}
