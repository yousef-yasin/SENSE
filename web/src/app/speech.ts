import { signal } from '@preact/signals';
import { SenseError, type SenseErrorCode } from './errors';

interface RecognitionResultList {
  length: number;
  [index: number]: { 0: { transcript: string }; isFinal: boolean };
}

interface Recognition {
  lang: string;
  continuous: boolean;
  interimResults: boolean;
  start(): void;
  stop(): void;
  abort(): void;
  onresult: ((event: { results: RecognitionResultList }) => void) | null;
  onerror: ((event: { error: string }) => void) | null;
  onend: (() => void) | null;
}

type RecognitionConstructor = new () => Recognition;

function recognitionConstructor(): RecognitionConstructor | undefined {
  const scope = window as unknown as { SpeechRecognition?: RecognitionConstructor; webkitSpeechRecognition?: RecognitionConstructor };
  return scope.SpeechRecognition ?? scope.webkitSpeechRecognition;
}

const errorCodes: Record<string, SenseErrorCode> = {
  'not-allowed': 'speechDenied',
  'service-not-allowed': 'speechDenied',
  'no-speech': 'speechNoSpeech',
  network: 'speechNetwork',
  'audio-capture': 'microphoneMissing',
};

/** Browser speech recognition. Whether audio leaves the device depends on the browser. */
export class SpeechTranscriber {
  readonly transcript = signal('');
  readonly isRecording = signal(false);
  readonly error = signal<SenseError | undefined>(undefined);

  private recognition: Recognition | undefined;
  private ended: Promise<void> = Promise.resolve();

  static get isSupported(): boolean {
    return typeof window !== 'undefined' && recognitionConstructor() !== undefined;
  }

  /** Must be called from a user gesture. */
  start() {
    if (this.isRecording.value) return;
    const Constructor = recognitionConstructor();
    if (!Constructor) throw new SenseError('speechUnsupported');

    this.transcript.value = '';
    this.error.value = undefined;
    const recognition = new Constructor();
    recognition.lang = navigator.language || 'en-US';
    recognition.continuous = true;
    recognition.interimResults = true;

    let finishEnded: () => void = () => {};
    this.ended = new Promise((resolve) => (finishEnded = resolve));

    recognition.onresult = (event) => {
      let text = '';
      for (let i = 0; i < event.results.length; i++) text += event.results[i][0].transcript;
      this.transcript.value = text.trim();
    };
    recognition.onerror = (event) => {
      if (event.error === 'aborted') return;
      if (event.error === 'no-speech' && this.transcript.value) return;
      this.error.value = new SenseError(errorCodes[event.error] ?? 'speechFailed');
    };
    recognition.onend = () => {
      this.isRecording.value = false;
      this.recognition = undefined;
      finishEnded();
    };

    this.recognition = recognition;
    recognition.start();
    this.isRecording.value = true;
  }

  async finish(): Promise<string> {
    if (this.recognition) {
      this.recognition.stop();
      await Promise.race([this.ended, new Promise((resolve) => setTimeout(resolve, 2000))]);
    }
    return this.transcript.value.trim();
  }

  cancel() {
    this.recognition?.abort();
    this.recognition = undefined;
    this.isRecording.value = false;
  }
}

export const speech = new SpeechTranscriber();
