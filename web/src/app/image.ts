import { SenseError } from './errors';

export interface PreparedImage {
  canvas: HTMLCanvasElement;
  blob: Blob;
}

function loadImage(blob: Blob): Promise<HTMLImageElement> {
  return new Promise((resolve, reject) => {
    const url = URL.createObjectURL(blob);
    const image = new Image();
    image.onload = () => {
      URL.revokeObjectURL(url);
      resolve(image);
    };
    image.onerror = () => {
      URL.revokeObjectURL(url);
      reject(new SenseError('imageUnreadable'));
    };
    image.src = url;
  });
}

function canvasToJPEG(canvas: HTMLCanvasElement, quality = 0.82): Promise<Blob> {
  return new Promise((resolve, reject) => {
    canvas.toBlob((blob) => (blob ? resolve(blob) : reject(new SenseError('imageUnreadable'))), 'image/jpeg', quality);
  });
}

function drawScaled(source: CanvasImageSource, width: number, height: number, maxDimension: number): HTMLCanvasElement {
  const scale = Math.min(1, maxDimension / Math.max(width, height));
  const canvas = document.createElement('canvas');
  canvas.width = Math.max(1, Math.round(width * scale));
  canvas.height = Math.max(1, Math.round(height * scale));
  const context = canvas.getContext('2d');
  if (!context) throw new SenseError('imageUnreadable');
  context.drawImage(source, 0, 0, canvas.width, canvas.height);
  return canvas;
}

/** Decodes a photo (respecting its orientation), limits it to 2048 px and re-encodes it as JPEG. */
export async function prepareImage(file: Blob, maxDimension = 2048): Promise<PreparedImage> {
  const image = await loadImage(file);
  if (!image.naturalWidth || !image.naturalHeight) throw new SenseError('imageUnreadable');
  const canvas = drawScaled(image, image.naturalWidth, image.naturalHeight, maxDimension);
  return { canvas, blob: await canvasToJPEG(canvas) };
}

export async function captureVideoFrame(video: HTMLVideoElement, maxDimension = 2048): Promise<PreparedImage> {
  if (!video.videoWidth || !video.videoHeight) throw new SenseError('imageUnreadable');
  const canvas = drawScaled(video, video.videoWidth, video.videoHeight, maxDimension);
  return { canvas, blob: await canvasToJPEG(canvas) };
}
