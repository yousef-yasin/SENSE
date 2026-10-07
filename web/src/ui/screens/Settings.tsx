import { useEffect, useState } from 'preact/hooks';
import { Bell, Camera, ChevronRight, Download, Mic, Sparkles, Trash2 } from 'lucide-preact';
import { notificationPermission, requestNotificationPermission } from '../../app/reminders';
import { settings } from '../../app/settings';
import { SpeechTranscriber } from '../../app/speech';
import { eraseAll, memories } from '../../app/store';
import { Group, NavBar } from '../components';
import { installPrompt, isIOS, isStandalone, promptInstall } from '../install';
import { confirmDestructive, navigate, showError } from '../state';

type PermissionLabel = 'Allowed' | 'Off' | 'Asked when used' | 'Not supported';

async function queryPermission(name: 'camera' | 'microphone'): Promise<PermissionLabel> {
  if (name === 'camera' && !navigator.mediaDevices?.getUserMedia) return 'Not supported';
  try {
    const status = await navigator.permissions.query({ name: name as PermissionName });
    if (status.state === 'granted') return 'Allowed';
    if (status.state === 'denied') return 'Off';
  } catch {
    // Some browsers can't report this permission; it's requested when the feature is used.
  }
  return 'Asked when used';
}

function PermissionRow(props: { icon: typeof Bell; title: string; purpose: string; state: string; action?: { label: string; run: () => void } }) {
  const Icon = props.icon;
  return (
    <div class="row permission-row">
      <Icon size={20} class="tint" aria-hidden="true" />
      <div class="grow">
        <div>{props.title}</div>
        <div class="caption secondary">{props.purpose}</div>
      </div>
      {props.action ? (
        <button class="small-button" onClick={props.action.run}>
          {props.action.label}
        </button>
      ) : (
        <span class="secondary small">{props.state}</span>
      )}
    </div>
  );
}

export function Settings() {
  const [camera, setCamera] = useState<PermissionLabel>('Asked when used');
  const [microphone, setMicrophone] = useState<PermissionLabel>('Asked when used');
  const notifications = notificationPermission.value;

  useEffect(() => {
    queryPermission('camera').then(setCamera);
    queryPermission('microphone').then(setMicrophone);
  }, []);

  const erase = async () => {
    if (!(await confirmDestructive('Erase all SENSE data?', 'All memories, photos and reminders will be permanently deleted from this device.', 'Erase Everything'))) return;
    await eraseAll().catch(showError);
  };

  return (
    <div class="screen">
      <NavBar title="Settings" large back backLabel="SENSE" />
      <div class="grouped">
        {!isStandalone() && (
          <Group
            header="Install"
            footer={
              installPrompt.value
                ? 'Installing adds SENSE to your home screen or Start menu and opens it in its own window.'
                : isIOS()
                  ? 'In Safari, tap the Share button, then “Add to Home Screen”. SENSE then opens full screen like an app and can send notifications.'
                  : 'Use your browser menu to install SENSE as an app, for example “Install SENSE” in Chrome or Edge.'
            }
          >
            {installPrompt.value ? (
              <button class="row button-row icon-row tint" onClick={promptInstall}>
                <Download size={20} aria-hidden="true" /> Install SENSE
              </button>
            ) : (
              <div class="row icon-row">
                <Download size={20} class="tint" aria-hidden="true" /> Add SENSE to your Home Screen
              </div>
            )}
          </Group>
        )}

        <Group header="Permissions" footer="SENSE only asks for access when you use a feature that needs it.">
          <PermissionRow icon={Camera} title="Camera" purpose="Read text when you look at something with the live camera." state={camera} />
          <PermissionRow
            icon={Mic}
            title="Microphone"
            purpose={SpeechTranscriber.isSupported ? 'Hear you only while a voice capture is open.' : "Voice input isn't supported in this browser."}
            state={SpeechTranscriber.isSupported ? microphone : 'Not supported'}
          />
          <PermissionRow
            icon={Bell}
            title="Notifications"
            purpose="Deliver the reminders you create."
            state={notifications === 'granted' ? 'Allowed' : notifications === 'denied' ? 'Off' : 'Not supported'}
            action={notifications === 'default' ? { label: 'Allow', run: () => void requestNotificationPermission() } : undefined}
          />
        </Group>

        <Group
          header="Privacy"
          footer="Photos are read by on-device text recognition that runs in this browser. Voice input uses your browser's speech recognition; depending on the browser, audio may be processed by Apple or Google."
        >
          <div class="row">Your captures stay on this device</div>
        </Group>

        <Group header="Intelligence">
          <button class="row button-row icon-row" onClick={() => navigate('#/settings/understanding')}>
            <Sparkles size={20} class="tint" aria-hidden="true" />
            <span class="grow">Understanding</span>
            <span class="secondary">{settings.providerMode.value === 'onDevice' ? 'On this device' : 'Custom provider'}</span>
            <ChevronRight size={18} class="tertiary" aria-hidden="true" />
          </button>
        </Group>

        <Group header="Data" footer="Memories, photos and reminders are stored only in this browser on this device. Clearing your browser's website data also removes them.">
          <div class="row spread">
            <span>Memories on this device</span>
            <span class="secondary">{memories.value.length}</span>
          </div>
          <button class="row button-row icon-row destructive" onClick={erase}>
            <Trash2 size={20} aria-hidden="true" /> Erase All SENSE Data
          </button>
        </Group>

        <Group header="About">
          <div class="row spread">
            <span>Version</span>
            <span class="secondary">{__APP_VERSION__} (web)</span>
          </div>
        </Group>
      </div>
    </div>
  );
}
