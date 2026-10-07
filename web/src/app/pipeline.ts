import { type CaptureInput, type CaptureSource, type Understanding, inputIsEmpty, makeInput } from '../core/models';
import { type IntelligenceProvider, OnDeviceIntelligence, OpenAICompatibleIntelligence, ResilientIntelligence } from '../core/provider';
import { SenseError } from './errors';
import { type PreparedImage, prepareImage } from './image';
import { recognizeText } from './ocr';
import { remoteConfiguration } from './settings';

export interface CaptureDraft {
  id: string;
  input: CaptureInput;
  understanding: Understanding;
  image?: Blob;
}

class OfflineIntelligence implements IntelligenceProvider {
  readonly identifier = 'offline';

  async understand(input: CaptureInput): Promise<Understanding> {
    const understanding = await new OnDeviceIntelligence().understand(input);
    return { ...understanding, origin: 'onDeviceFallback' };
  }
}

function provider(): IntelligenceProvider {
  const configuration = remoteConfiguration();
  if (!configuration) return new OnDeviceIntelligence();
  if (!navigator.onLine) return new OfflineIntelligence();
  return new ResilientIntelligence(new OpenAICompatibleIntelligence(configuration));
}

async function understand(input: CaptureInput, image?: Blob): Promise<CaptureDraft> {
  const understanding = await provider().understand(input);
  return { id: crypto.randomUUID(), input, understanding, image };
}

export type ProgressHandler = (message: string) => void;

export async function processPreparedImage(prepared: PreparedImage, source: CaptureSource, onProgress?: ProgressHandler): Promise<CaptureDraft> {
  const text = await recognizeText(prepared.canvas, (fraction, status) => {
    if (status === 'recognizing text') onProgress?.(`Reading text… ${Math.round(fraction * 100)}%`);
    else onProgress?.('Preparing text recognition…');
  });
  const input = makeInput(source, text);
  if (inputIsEmpty(input)) throw new SenseError('nothingRecognized');
  onProgress?.('Understanding…');
  return understand(input, prepared.blob);
}

export async function processImageFile(file: Blob, source: CaptureSource, onProgress?: ProgressHandler): Promise<CaptureDraft> {
  const prepared = await prepareImage(file);
  return processPreparedImage(prepared, source, onProgress);
}

export async function processText(text: string, source: CaptureSource): Promise<CaptureDraft> {
  const input = makeInput(source, text);
  if (inputIsEmpty(input)) throw new SenseError('nothingRecognized');
  return understand(input);
}
