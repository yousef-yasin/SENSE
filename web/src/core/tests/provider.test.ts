import { describe, expect, it } from 'vitest';
import { ContentAnalyzer } from '../contentAnalyzer';
import { makeInput } from '../models';
import { type HTTPClient, OnDeviceIntelligence, OpenAICompatibleIntelligence, ResilientIntelligence } from '../provider';
import { calendar, now } from './fixture';

const stub = (status: number, body: string): HTTPClient => ({ send: async () => ({ status, body }) });
const failing: HTTPClient = {
  send: async () => {
    throw new TypeError('Failed to fetch');
  },
};
const configuration = { baseURL: 'http://localhost:11434/v1', model: 'llama3.2', apiKey: 'test-key' };
const local = new OnDeviceIntelligence(new ContentAnalyzer(calendar, false), () => now);
const input = makeInput('camera', 'Registration closes October 8 at 4 PM.', [], now);
const chatResponse = (content: string) => JSON.stringify({ choices: [{ message: { role: 'assistant', content } }] });

describe('Providers', () => {
  it('refinement merges with local understanding', async () => {
    const content = '```json\n{"kind":"announcement","title":"Registration deadline","summary":"Registration closes Oct 8 at 4 PM.","highlights":["Bring your student ID"]}\n```';
    const provider = new OpenAICompatibleIntelligence(configuration, local, stub(200, chatResponse(content)));
    const result = await provider.understand(input);
    expect(result.origin).toBe('remote');
    expect(result.kind).toBe('announcement');
    expect(result.title).toBe('Registration deadline');
    expect(result.highlights.some((h) => h.kind === 'info' && h.text === 'Bring your student ID')).toBe(true);
    expect(result.entities.some((e) => e.kind === 'date')).toBe(true);
  });

  it('request shape', () => {
    const request = new OpenAICompatibleIntelligence(configuration, local, failing).makeRequest(input);
    expect(request.url).toBe('http://localhost:11434/v1/chat/completions');
    expect(request.method).toBe('POST');
    expect(request.headers.Authorization).toBe('Bearer test-key');
    expect(JSON.parse(request.body).model).toBe('llama3.2');
  });

  it('falls back to on-device when provider fails', async () => {
    const provider = new ResilientIntelligence(new OpenAICompatibleIntelligence(configuration, local, failing), local);
    const result = await provider.understand(input);
    expect(result.origin).toBe('onDeviceFallback');
    expect(result.highlights.length).toBeGreaterThan(0);
  });

  it('HTTP error falls back', async () => {
    const provider = new ResilientIntelligence(new OpenAICompatibleIntelligence(configuration, local, stub(401, '{}')), local);
    expect((await provider.understand(input)).origin).toBe('onDeviceFallback');
  });

  it('unreadable content is rejected', () => {
    expect(() => OpenAICompatibleIntelligence.parseRefinement(chatResponse('not json'))).toThrow();
  });

  it('ignores unknown kind', () => {
    const base = { kind: 'note' as const, title: 'A', summary: 'B', highlights: [], entities: [], suggestions: [], tags: [], origin: 'onDevice' as const };
    const merged = OpenAICompatibleIntelligence.merge(base, { kind: 'spaceship' });
    expect(merged.kind).toBe('note');
    expect(merged.title).toBe('A');
  });
});
