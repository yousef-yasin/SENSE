import { render } from 'preact';
import { registerSW } from 'virtual:pwa-register';
import { startReminderScheduler } from './app/reminders';
import { loadAll } from './app/store';
import { App } from './ui/App';
import './styles.css';

registerSW({ immediate: true });

render(<App />, document.getElementById('app')!);

loadAll().then(startReminderScheduler);
