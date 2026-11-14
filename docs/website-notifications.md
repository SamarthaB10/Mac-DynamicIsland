# Website notifications

Mac Island will give users one place to see alerts from selected websites near the notch.

## Agreed behavior

- Use existing browser alerts from X, LinkedIn, Gmail, and YouTube for the first version. Support is not yet verified.
- When an alert arrives with the island closed, jiggle once, then show a bell and unread count. Keep the island closed until the user opens it.
- Put notification cards in Notifications, identified by a bell.
- Give each card three actions: Open page, Mark as read, and Dismiss.
- Support Ardia first. Alerts must arrive while Ardia runs, even when the site's tab is closed.
- Ardia must work as it is. Do not require changes to Ardia's code.
- Mark a card as read when the user opens its original page or selects Mark as read. Opening the Notifications list does not mark its cards as read.
- Keep website and island read state in agreement in both directions. A read card stays saved until dismissed.
- Mark as read also clears the matching macOS alert, while keeping the read card in the island.
- Dismiss removes the island card and requests removal of the macOS alert and a change of the website item to read. It does not delete the website item.
- If an external update fails after Dismiss, keep the island card removed and show that the other update failed.
- If an external update fails after Mark as read, keep the card read locally and show the failed update with Retry.
- After Dismiss, show failed updates in a notice at the top of Notifications. Keep the notice until the update succeeds or the user selects Clear. Include Retry.
- Keep cards across app restarts until the user dismisses them.

## Open decisions

The connection method is not yet agreed. Delivery with a closed site tab and changes to the website and macOS alerts need feasibility checks before implementation.

The user authorized implementation after answering questions 15 and 16. The first step is to verify a connection that can meet these requirements without changing Ardia. No reduction of the requirements is authorized.

## Current implementation state

The bell section and a live Ardia text-feed connection are implemented for the four source origins. The view follows the supplied two-column reference, uses local source logos, and has a 440-by-305-point panel, about half the area of its initial 620-by-430-point version. Cards, source choices, and connection choice are saved locally. Unread cards add an activity summary and a compact bell/count. New arrivals request one short jiggle without opening the island; Reduce Motion disables the motion.

An X test alert reached the running Mac Island app and was saved as a card. The native view showed its source count, title, body, and actions. The host build and existing activity and timer checks passed. Full post/article content, exact destination links, website read state, and removal of matching macOS alerts are incomplete. A source-home-page fallback does not mark the card read. Local read/dismiss actions show one capability notice; repeated notices and a Retry button that cannot perform an update have been removed.

The source connection must be completed before this feature can meet the full requirements. The draft PR records this gap. The current section must not be described as a complete website notification integration.

The user authorized repair of the browser connection. Ardia's Advanced settings showed command control as off. After enabling that setting, `ardia tabs --flat --json` succeeded. Ardia's code was not changed.

Read-only checks through the browser returned an active service worker for both X and YouTube. X's browser notification permission was `default`; YouTube's was `granted`. Both service-worker notification lists were empty. The temporary YouTube tab was closed; the user's X tab was kept. No existing alert was marked as read or dismissed.

No notification delivery with a site tab closed, original-alert action, or website read update has been observed in this task. The remaining work is to establish a connection that meets the full requirements. Browser command access alone does not prove that connection.

## Live test results

The user approved enabling X's browser notification permission and creating clearly labeled test alerts on X and YouTube. X's permission changed to `granted`.

- A test service-worker notification from X reached `ardia events --json notification.shown`.
- A test service-worker notification from YouTube reached the same event stream.
- Both observed events contained `windowId`, `tabId`, `profile`, `origin`, `title`, and `body`. Neither event supplied a notification identifier, destination link, image, or action.
- On each site, `registration.getNotifications` returned no handle for the test notification after `showNotification` completed. This query therefore did not establish a way to inspect or close the original alert in this Ardia build.
- A close was requested for the separate X page test notification. The two service-worker test alerts had no returned handles to close; their removal from macOS Notification Center was not verified.
- The browser session closed its two test tabs. Existing account notifications were not marked as read or dismissed.

These tests establish delivery of test text through Ardia's event stream while the site tab exists. They do not establish delivery after the site tab closes, exact destination links, removal of matching macOS alerts, or shared website read state. LinkedIn and Gmail have not had live alert tests.


## Source checks

Checked on 2026-11-13:

- [Ardia's notification handler](https://github.com/ardia-browser/ardia/blob/eac3486f6dcf074251bb18086fd1890ce7906fa5/apps/browser/src/state/site/webNotifications.ts) sends a notification event and posts the macOS alert. It requires an existing tab and window. Its response handler returns without forwarding an action when the tab no longer exists. This code does not prove delivery or actions with the site tab closed.
- The same handler keeps the macOS and browser notification identifiers inside Ardia. It can remove macOS alerts through Ardia's own notification code. A connection that lets Mac Island request this action is not yet verified.
- Website read state is a separate requirement. Closing a browser notification does not, by itself, prove that the website marks its item as read.
- The [YouTube Data API reference](https://developers.google.com/youtube/data/reference/rest) lists no notification inbox resource or method to mark its items as read. Its [push service](https://developers.google.com/youtube/data/guides/push_notifications) covers video uploads and title or description changes. This does not establish support for the requested personal alerts or read state.
