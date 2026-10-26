# Automatic message imports

1. Install and launch Pocket Ledger once.
2. In Apple Shortcuts, create a personal automation triggered by receiving a **Message**. Match a bank sender or message content such as `INR`. UI labels vary by iOS version.
3. Add the app action **Import Bank Message**. Set its **Message** parameter to the received message's **content/text** from Shortcut Input. Use **Get Text from Input** if Shortcuts exposes a message object instead of text. Leave Sender blank unless the trigger supplies it.
4. Enable automatic execution without confirmation (for example, **Run Immediately**). Complete permissions on the first run.
5. Repeat for bank templates using `Rs` or `₹`, or additional bank senders. The parser deduplicates overlapping deliveries when it can identify the same transaction.
6. During setup, add **Show Notification** with the import action's returned result. This reports saved, duplicate, ignored, or unrecognized messages without echoing financial data.
7. Test a real incoming transaction with the app closed, then with the phone locked. After restarting the phone, unlock it once before relying on background imports.

Recognized messages are saved immediately. Review flags indicate saved records needing corrections; they do not postpone saving. OTPs, payment requests, reminders, and failed/declined transactions are ignored. Unrecognized/ambiguous amounts must be added manually.

Old messages are imported through the app's paste screen. If there is no date in the message, the import uses the current receipt date; correct older transactions afterward.

The app does not create or install personal automations, read your inbox, or guarantee that iOS will execute every trigger. Disable/delete the personal automations in Shortcuts to stop capture.

References:
- [Apple: Communication triggers](https://support.apple.com/en-ae/guide/shortcuts/apdd711f9dff/ios)
- [Apple: App Intent authentication policy](https://developer.apple.com/documentation/appintents/appintent/authenticationpolicy)
- [Apple: Message-filter privacy restrictions](https://developer.apple.com/documentation/identitylookup/sms-and-mms-message-filtering)
