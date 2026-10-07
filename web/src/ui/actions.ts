import { IntentParser } from '../core/intentParser';
import type { CaptureSource } from '../core/models';
import type { PreparedImage } from '../app/image';
import { type CaptureDraft, processImageFile, processPreparedImage, processText } from '../app/pipeline';
import { SenseError } from '../app/errors';
import { speech, SpeechTranscriber } from '../app/speech';
import { memories } from '../app/store';
import { navigate, processing, sheet, showAlert, showError, showLook } from './state';

const intentParser = new IntentParser();
let fileInput: HTMLInputElement | undefined;

export function registerFileInput(input: HTMLInputElement | null) {
  fileInput = input ?? undefined;
}

/** Opens the system picker; on iPhone it offers Take Photo and Photo Library. */
export function chooseImage() {
  if (!fileInput) return;
  fileInput.value = '';
  fileInput.click();
}

async function withProcessing(message: string, work: (update: (message: string) => void) => Promise<CaptureDraft>) {
  processing.value = message;
  try {
    const draft = await work((next) => (processing.value = next));
    sheet.value = { type: 'review', draft };
  } catch (error) {
    showError(error);
  } finally {
    processing.value = undefined;
  }
}

export function captureFile(file: File) {
  const source: CaptureSource = file.lastModified && Date.now() - file.lastModified < 120_000 ? 'camera' : 'photo';
  void withProcessing('Reading photo…', (update) => processImageFile(file, source, update));
}

export function captureFrame(prepared: PreparedImage) {
  void withProcessing('Reading text…', (update) => processPreparedImage(prepared, 'live', update));
}

export function startLook() {
  if (!navigator.mediaDevices?.getUserMedia) {
    showError(new SenseError('cameraUnavailable'));
    return;
  }
  showLook.value = true;
}

/** Starts listening inside the tap that opens the voice sheet, as iOS Safari requires. */
export function startVoice() {
  if (SpeechTranscriber.isSupported) {
    try {
      speech.start();
    } catch {
      // The sheet shows the microphone button so the person can try again.
    }
  }
  sheet.value = { type: 'voice' };
}

export async function runCommand(text: string, source: CaptureSource) {
  const trimmed = text.trim();
  if (!trimmed) return;
  const intent = intentParser.parse(trimmed);
  switch (intent.type) {
    case 'analyzeSurroundings':
      startLook();
      return;
    case 'recallSimilar': {
      const latest = memories.value[0];
      if (!latest) showAlert('SENSE', "Capture something first, then ask whether you've seen it before.");
      else navigate(`#/similar/${latest.id}`);
      return;
    }
    case 'search':
      navigate(`#/memories?q=${encodeURIComponent(intent.query)}`);
      return;
    case 'remind': {
      const draft = { ...intent.draft };
      const memory = draft.refersToContext ? memories.value[0] : undefined;
      if (draft.refersToContext) draft.title = memory?.title || '';
      sheet.value = {
        type: 'reminder',
        request: { draft, memoryId: memory?.id, memoryTitle: memory?.title || undefined, body: memory?.summary ?? '' },
      };
      return;
    }
    case 'capture':
      await withProcessing('Understanding…', () => processText(intent.text, source));
  }
}
