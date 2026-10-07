export type SenseErrorCode =
  | 'cameraUnavailable'
  | 'cameraDenied'
  | 'nothingRecognized'
  | 'imageUnreadable'
  | 'ocrUnavailable'
  | 'speechUnsupported'
  | 'speechDenied'
  | 'speechNoSpeech'
  | 'speechNetwork'
  | 'microphoneMissing'
  | 'speechFailed'
  | 'reminderInPast'
  | 'storageUnavailable';

const messages: Record<SenseErrorCode, string> = {
  cameraUnavailable: "The camera isn't available in this browser. You can still choose a photo and SENSE will understand it.",
  cameraDenied: 'Camera access is turned off for this site. You can enable it in your browser settings, or choose a photo instead.',
  nothingRecognized: "SENSE couldn't find any text. Try again with better lighting or move closer.",
  imageUnreadable: "That image couldn't be read.",
  ocrUnavailable: "Text recognition couldn't start. It's downloaded the first time you use it, so check your connection and try again.",
  speechUnsupported: "Voice input isn't supported in this browser. Use Text instead; your keyboard's dictation button works there.",
  speechDenied: "Microphone or speech recognition access is turned off for this site. Allow it in your browser settings, or use your keyboard's dictation in Text.",
  speechNoSpeech: "SENSE didn't hear anything. Tap the microphone and try again.",
  speechNetwork: "Your browser's speech recognition couldn't be reached. Check your connection and try again.",
  microphoneMissing: 'No microphone was found.',
  speechFailed: "Speech recognition isn't available right now. Try again in a moment.",
  reminderInPast: 'Choose a time in the future.',
  storageUnavailable: "Your memories couldn't be opened in this browser. Private browsing can block storage.",
};

export class SenseError extends Error {
  constructor(readonly code: SenseErrorCode) {
    super(messages[code]);
    this.name = 'SenseError';
  }
}

export function describeError(error: unknown): string {
  if (error instanceof Error) return error.message;
  return String(error);
}
