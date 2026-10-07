self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const memoryId = event.notification.data && event.notification.data.memoryId;
  const target = new URL(memoryId ? `./#/memory/${memoryId}` : './#/reminders', self.registration.scope).href;
  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clients) => {
      for (const client of clients) {
        if ('focus' in client) {
          if ('navigate' in client) client.navigate(target).catch(() => undefined);
          return client.focus();
        }
      }
      return self.clients.openWindow(target);
    }),
  );
});
