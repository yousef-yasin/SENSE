import { useState } from 'preact/hooks';
import { makeInput } from '../../core/models';
import { OpenAICompatibleIntelligence, ProviderError } from '../../core/provider';
import { remoteConfiguration, settings } from '../../app/settings';
import { Group, NavBar } from '../components';

export function Understanding() {
  const [testResult, setTestResult] = useState<string>();
  const [testing, setTesting] = useState(false);
  const mode = settings.providerMode.value;
  const configuration = remoteConfiguration();

  const test = async () => {
    if (!configuration) return;
    setTesting(true);
    setTestResult(undefined);
    try {
      const provider = new OpenAICompatibleIntelligence(configuration);
      const result = await provider.understand(makeInput('text', 'Library notice: books borrowed this month are due back by Friday at 6 PM.'));
      setTestResult(`Connected. The server summarized a sample as: “${result.title}”`);
    } catch (error) {
      if (error instanceof ProviderError) {
        setTestResult(error.code === 'httpStatus' ? `The server responded with status ${error.status}.` : 'The server responded, but not in the expected format. Check the model name.');
      } else {
        setTestResult("The server couldn't be reached. It must use HTTPS and allow requests from this site (CORS).");
      }
    } finally {
      setTesting(false);
    }
  };

  const field = (label: string, value: string, onInput: (value: string) => void, placeholder: string, type: 'text' | 'url' | 'password' = 'text') => (
    <label class="row field-row">
      <span>{label}</span>
      <input type={type as "text"} value={value} placeholder={placeholder} autocapitalize="off" autocorrect="off" spellcheck={false} onInput={(e) => onInput((e.target as HTMLInputElement).value)} />
    </label>
  );

  return (
    <div class="screen">
      <NavBar title="Understanding" back backLabel="Settings" />
      <div class="grouped">
        <Group footer="On-device understanding is free, works offline and never sends your captures anywhere. A server can write richer titles and summaries; dates, reminders and search always stay on this device.">
          {(['onDevice', 'openAICompatible'] as const).map((option) => (
            <button class="row button-row spread" onClick={() => (settings.providerMode.value = option)} aria-pressed={mode === option}>
              <span>{option === 'onDevice' ? 'On this device' : 'OpenAI-compatible server'}</span>
              {mode === option && <span class="tint checkmark">✓</span>}
            </button>
          ))}
        </Group>

        {mode === 'openAICompatible' && (
          <>
            <Group
              header="Server"
              footer="Works with any service that offers an OpenAI-compatible chat completions endpoint over HTTPS and allows requests from this site. A server on your local network over plain HTTP, such as a default Ollama install, can't be reached from the web app; use the iPhone app for that."
            >
              {field('Base URL', settings.providerBaseURL.value, (v) => (settings.providerBaseURL.value = v), 'https://api.example.com/v1', 'url')}
              {field('Model', settings.providerModel.value, (v) => (settings.providerModel.value = v), 'llama3.2')}
            </Group>
            <Group header="API Key" footer="Stored in this browser's local storage on this device. Local servers usually don't need one.">
              {field('Key', settings.apiKey.value, (v) => (settings.apiKey.value = v), 'Optional', 'password')}
            </Group>
            <Group footer="When a server is configured, the text SENSE recognizes in each capture is sent to it. Photos and audio are never sent. If the server can't be reached, SENSE falls back to on-device understanding.">
              <button class="row button-row tint spread" onClick={test} disabled={!configuration || testing}>
                <span>Test Connection</span>
                {testing && <span class="spinner small" />}
              </button>
              {testResult && <div class="row secondary small">{testResult}</div>}
            </Group>
          </>
        )}
      </div>
    </div>
  );
}
