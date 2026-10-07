import type { Worker } from 'tesseract.js';
import { SenseError } from './errors';

let worker: Promise<Worker> | undefined;
let progressHandler: ((fraction: number, status: string) => void) | undefined;

const minimumLineConfidence = 55;

async function getWorker(): Promise<Worker> {
  worker ??= (async () => {
    const { createWorker } = await import('tesseract.js');
    return createWorker('eng', 1, {
      logger: (message) => progressHandler?.(message.progress, message.status),
    });
  })();
  try {
    return await worker;
  } catch {
    worker = undefined;
    throw new SenseError('ocrUnavailable');
  }
}

/** Recognizes printed text on this device with Tesseract. Low-confidence lines are dropped. */
export async function recognizeText(canvas: HTMLCanvasElement, onProgress?: (fraction: number, status: string) => void): Promise<string> {
  progressHandler = onProgress;
  try {
    const instance = await getWorker();
    const { data } = await instance.recognize(canvas, {}, { text: true, blocks: true });
    if (!data.blocks) return data.text.trim();
    const lines: string[] = [];
    for (const block of data.blocks) {
      for (const paragraph of block.paragraphs) {
        for (const line of paragraph.lines) {
          const text = line.text.trim();
          const meaningful = (text.match(/[\p{L}\p{N}]/gu) ?? []).length;
          if (line.confidence >= minimumLineConfidence && meaningful >= 2) lines.push(text);
        }
      }
    }
    return lines.join('\n');
  } finally {
    progressHandler = undefined;
  }
}
