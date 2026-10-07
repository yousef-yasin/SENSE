import { ContentAnalyzer } from './contentAnalyzer';
import { type CaptureInput, MEMORY_KINDS, type Understanding, inputIsEmpty, isMemoryKind, labelDisplayName } from './models';
import { truncated } from './text';

export interface IntelligenceProvider {
  readonly identifier: string;
  understand(input: CaptureInput): Promise<Understanding>;
}

export class OnDeviceIntelligence implements IntelligenceProvider {
  readonly identifier = 'on-device';

  constructor(
    readonly analyzer: ContentAnalyzer = new ContentAnalyzer(),
    private readonly clock: () => Date = () => new Date(),
  ) {}

  async understand(input: CaptureInput): Promise<Understanding> {
    return this.analyzer.analyze(input, this.clock());
  }
}

export class ResilientIntelligence implements IntelligenceProvider {
  constructor(
    readonly primary: IntelligenceProvider,
    readonly fallback: OnDeviceIntelligence = new OnDeviceIntelligence(),
  ) {}

  get identifier() {
    return this.primary.identifier;
  }

  async understand(input: CaptureInput): Promise<Understanding> {
    try {
      return await this.primary.understand(input);
    } catch {
      const understanding = await this.fallback.understand(input);
      return { ...understanding, origin: 'onDeviceFallback' };
    }
  }
}

export type ProviderErrorCode = 'invalidResponse' | 'httpStatus' | 'unreadableContent';

export class ProviderError extends Error {
  constructor(
    readonly code: ProviderErrorCode,
    readonly status?: number,
  ) {
    super(code === 'httpStatus' ? `HTTP ${status}` : code);
  }
}

export interface HTTPRequest {
  url: string;
  method: string;
  headers: Record<string, string>;
  body: string;
  timeoutMs: number;
}

export interface HTTPClient {
  send(request: HTTPRequest): Promise<{ status: number; body: string }>;
}

export const fetchClient: HTTPClient = {
  async send(request) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), request.timeoutMs);
    try {
      const response = await fetch(request.url, { method: request.method, headers: request.headers, body: request.body, signal: controller.signal });
      return { status: response.status, body: await response.text() };
    } finally {
      clearTimeout(timer);
    }
  },
};

export interface RemoteProviderConfiguration {
  baseURL: string;
  model: string;
  apiKey?: string;
  timeoutMs?: number;
}

export interface Refinement {
  kind?: string | null;
  title?: string | null;
  summary?: string | null;
  highlights?: string[] | null;
}

export class OpenAICompatibleIntelligence implements IntelligenceProvider {
  readonly identifier = 'openai-compatible';

  constructor(
    readonly configuration: RemoteProviderConfiguration,
    readonly local: OnDeviceIntelligence = new OnDeviceIntelligence(),
    readonly client: HTTPClient = fetchClient,
  ) {}

  async understand(input: CaptureInput): Promise<Understanding> {
    const base = await this.local.understand(input);
    if (inputIsEmpty(input)) return base;
    const response = await this.client.send(this.makeRequest(input));
    if (response.status < 200 || response.status >= 300) throw new ProviderError('httpStatus', response.status);
    return OpenAICompatibleIntelligence.merge(base, OpenAICompatibleIntelligence.parseRefinement(response.body));
  }

  makeRequest(input: CaptureInput): HTTPRequest {
    const headers: Record<string, string> = { 'Content-Type': 'application/json' };
    if (this.configuration.apiKey) headers.Authorization = `Bearer ${this.configuration.apiKey}`;

    const system =
      'You turn text a person captured from the real world into a short structured memory. ' +
      `Respond with a single JSON object with keys: "kind" (one of: ${MEMORY_KINDS.join(', ')}), "title" (max 8 words), ` +
      '"summary" (one or two sentences stating what matters), "highlights" (array of up to 5 short strings: ' +
      'deadlines, warnings, requirements, or key facts). Use only information present in the input.';
    let user = `Source: ${input.source}\n`;
    if (input.imageLabels.length > 0) {
      user += `Visual labels: ${input.imageLabels.slice(0, 5).map((l) => labelDisplayName(l.identifier)).join(', ')}\n`;
    }
    user += `Text:\n${Array.from(input.text).slice(0, 6000).join('')}`;

    return {
      url: this.configuration.baseURL.replace(/\/+$/, '') + '/chat/completions',
      method: 'POST',
      headers,
      timeoutMs: this.configuration.timeoutMs ?? 20_000,
      body: JSON.stringify({
        model: this.configuration.model,
        temperature: 0.2,
        response_format: { type: 'json_object' },
        messages: [
          { role: 'system', content: system },
          { role: 'user', content: user },
        ],
      }),
    };
  }

  static parseRefinement(body: string): Refinement {
    let content: unknown;
    try {
      content = JSON.parse(body)?.choices?.[0]?.message?.content;
    } catch {
      throw new ProviderError('invalidResponse');
    }
    if (typeof content !== 'string') throw new ProviderError('invalidResponse');

    let json = content.trim();
    if (json.startsWith('```')) json = json.replace(/```json/g, '').replace(/```/g, '').trim();
    const start = json.indexOf('{');
    const end = json.lastIndexOf('}');
    if (start !== -1 && end !== -1 && start < end) json = json.slice(start, end + 1);

    let parsed: unknown;
    try {
      parsed = JSON.parse(json);
    } catch {
      throw new ProviderError('unreadableContent');
    }
    if (typeof parsed !== 'object' || parsed === null || Array.isArray(parsed)) throw new ProviderError('unreadableContent');
    const record = parsed as Record<string, unknown>;
    const optionalString = (v: unknown) => v === undefined || v === null || typeof v === 'string';
    if (!optionalString(record.kind) || !optionalString(record.title) || !optionalString(record.summary)) throw new ProviderError('unreadableContent');
    const highlights = record.highlights;
    if (!(highlights === undefined || highlights === null || (Array.isArray(highlights) && highlights.every((h) => typeof h === 'string')))) {
      throw new ProviderError('unreadableContent');
    }
    return record as Refinement;
  }

  static merge(base: Understanding, refinement: Refinement): Understanding {
    const result: Understanding = { ...base, highlights: [...base.highlights] };
    const kind = refinement.kind?.toLowerCase();
    if (kind && isMemoryKind(kind)) result.kind = kind;
    const title = refinement.title?.trim();
    if (title) result.title = truncated(title, 80);
    const summary = refinement.summary?.trim();
    if (summary) result.summary = truncated(summary, 400);
    const existing = new Set(base.highlights.map((h) => h.text.toLowerCase()));
    const additions = (refinement.highlights ?? [])
      .map((h) => h.trim())
      .filter((h) => h.length > 0 && !existing.has(h.toLowerCase()))
      .slice(0, 5)
      .map((h) => ({ kind: 'info' as const, text: truncated(h, 200) }));
    result.highlights.push(...additions);
    result.origin = 'remote';
    return result;
  }
}
