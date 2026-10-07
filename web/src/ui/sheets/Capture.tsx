import { useEffect, useRef, useState } from 'preact/hooks';
import { Mic, Square, X } from 'lucide-preact';
import { SenseError } from '../../app/errors';
import { captureVideoFrame } from '../../app/image';
import { speech, SpeechTranscriber } from '../../app/speech';
import { captureFrame, chooseImage, runCommand } from '../actions';
import { Sheet, SheetBar } from '../components';
import { sheet, showError, showLook } from '../state';

export function VoiceSheet() {
  const transcript = speech.transcript.value;
  const recording = speech.isRecording.value;
  const error = speech.error.value;
  const supported = SpeechTranscriber.isSupported;

  const close = () => {
    speech.cancel();
    sheet.value = undefined;
  };

  const toggle = async () => {
    if (recording) {
      const text = await speech.finish();
      if (!text) return;
      sheet.value = undefined;
      void runCommand(text, 'voice');
    } else {
      try {
        speech.start();
      } catch (failure) {
        showError(failure);
      }
    }
  };

  const status = !supported
    ? new SenseError('speechUnsupported').message
    : error
      ? error.message
      : transcript || (recording ? 'Listening…' : 'Tap the microphone to speak');

  return (
    <Sheet onClose={close} medium>
      <SheetBar
        title="Voice"
        leading={
          <button class="nav-button" onClick={close}>
            Cancel
          </button>
        }
      />
      <div class="voice">
        <div class={`voice-transcript ${transcript && !error ? '' : 'secondary'}`} aria-live="polite">
          {status}
        </div>
        {supported && !transcript && (
          <div class="voice-hints secondary">
            <div class="caption strong">Try saying</div>
            <div>“Remind me to call the lab tomorrow at 5.”</div>
            <div>“What did I capture yesterday?”</div>
            <div>“Have I seen this before?”</div>
          </div>
        )}
        {supported ? (
          <button class={`mic-button ${recording ? 'recording' : ''}`} onClick={toggle} aria-label={recording ? 'Stop and understand' : 'Start listening'}>
            <span class="mic-pulse" aria-hidden="true" />
            <span class="mic-core">{recording ? <Square size={28} fill="currentColor" /> : <Mic size={32} />}</span>
          </button>
        ) : (
          <button
            class="primary-button"
            onClick={() => {
              sheet.value = { type: 'text' };
            }}
          >
            Use Text Instead
          </button>
        )}
        {supported && <p class="caption secondary center">Your browser's speech recognition turns your voice into text. Depending on the browser, audio may be processed by Apple or Google.</p>}
      </div>
    </Sheet>
  );
}

export function TextSheet() {
  const [text, setText] = useState('');
  const field = useRef<HTMLTextAreaElement>(null);
  const trimmed = text.trim();

  useEffect(() => {
    field.current?.focus();
  }, []);

  const done = () => {
    if (!trimmed) return;
    sheet.value = undefined;
    void runCommand(trimmed, 'text');
  };

  return (
    <Sheet onClose={() => (sheet.value = undefined)} medium>
      <SheetBar
        title="Text"
        leading={
          <button class="nav-button" onClick={() => (sheet.value = undefined)}>
            Cancel
          </button>
        }
        trailing={
          <button class="nav-button strong" onClick={done} disabled={!trimmed}>
            Done
          </button>
        }
      />
      <div class="text-entry">
        <textarea
          ref={field}
          rows={5}
          placeholder="Write a note, a reminder or a question"
          value={text}
          onInput={(e) => setText((e.target as HTMLTextAreaElement).value)}
          onKeyDown={(e) => {
            if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) done();
          }}
        />
        <p class="caption secondary">SENSE works out whether this is something to remember, a reminder, or a question about your memories.</p>
      </div>
    </Sheet>
  );
}

export function LiveLook() {
  const video = useRef<HTMLVideoElement>(null);
  const [ready, setReady] = useState(false);
  const [failed, setFailed] = useState<string>();
  const [capturing, setCapturing] = useState(false);

  useEffect(() => {
    let stream: MediaStream | undefined;
    let cancelled = false;
    navigator.mediaDevices
      .getUserMedia({ video: { facingMode: { ideal: 'environment' }, width: { ideal: 1920 }, height: { ideal: 1080 } }, audio: false })
      .then((media) => {
        if (cancelled) {
          media.getTracks().forEach((t) => t.stop());
          return;
        }
        stream = media;
        if (video.current) {
          video.current.srcObject = media;
          void video.current.play().catch(() => undefined);
        }
      })
      .catch((error: DOMException) => {
        const code = error?.name === 'NotAllowedError' || error?.name === 'SecurityError' ? 'cameraDenied' : 'cameraUnavailable';
        setFailed(new SenseError(code).message);
      });
    return () => {
      cancelled = true;
      stream?.getTracks().forEach((t) => t.stop());
    };
  }, []);

  const close = () => (showLook.value = false);

  const capture = async () => {
    if (!video.current) return;
    setCapturing(true);
    try {
      const prepared = await captureVideoFrame(video.current);
      close();
      captureFrame(prepared);
    } catch (error) {
      setCapturing(false);
      showError(error);
    }
  };

  return (
    <div class="look" role="dialog" aria-label="Live view">
      <video ref={video} class="look-video" playsInline muted autoPlay onLoadedMetadata={() => setReady(true)} />
      <button class="look-close" onClick={close} aria-label="Close">
        <X size={22} />
      </button>
      {failed ? (
        <div class="look-unavailable">
          <div class="headline">Live view isn't available</div>
          <p class="secondary">{failed}</p>
          <button
            class="primary-button"
            onClick={() => {
              close();
              chooseImage();
            }}
          >
            Choose a Photo
          </button>
        </div>
      ) : (
        <div class="look-controls">
          <div class="secondary small">{ready ? 'Point at text, a sign or a document' : 'Starting camera…'}</div>
          <button class="primary-button" onClick={capture} disabled={!ready || capturing}>
            ✦ What's important here?
          </button>
        </div>
      )}
    </div>
  );
}
