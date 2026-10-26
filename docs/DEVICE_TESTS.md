# Device acceptance checks

These checks require full Xcode and an iPhone running iOS 27. Cloud checks require a paid developer membership, provisioned private container, and two devices on the same Apple Account. They have not yet been executed in this workspace.

## Installation and screens

- Build the local scheme for simulator and a signed iPhone. Confirm app name, icon, launch, tab bar, light/dark appearance, large text, VoiceOver labels, keyboard, and small-screen layouts.
- Add/edit/delete an INR transaction. Relaunch and verify persistence.
- Create, rename, reorder, and archive a category. Confirm historical transactions retain it and imports avoid it when archived.
- Save a merchant rule and import a second message for that merchant. Remove the rule and verify fallback suggestions.
- Check that expense minus refund totals exclude income and transfers. Test a month boundary and a negative net month.
- Search and filter, edit review entries, mark reviewed, export CSV, and verify CSV data in a spreadsheet.
- Export CSV, import it into an empty ledger, and compare dates, amounts, merchants, types, methods, banks, category names/IDs, symbols, tints, notes, and review flags. Repeat import to verify duplicates are skipped. Test old CSV headers without ID columns, quoted commas/quotes/newlines, formula-safe values, malformed rows, and restore after deleting a backed-up transaction.
- Set budgets for multiple categories and months. Confirm the selected Overview month shows the matching limit, percentage, and over-budget color; changing months should reveal the other month's limits. Test zero/blank to remove a budget and confirm existing transactions remain.
- Upgrade a copy of an existing V1 app store to this build and confirm transactions/categories/rules remain after the V1→V2 budget migration. If testing CloudDebug, confirm a budget created or changed on one device appears on the other.
- In Review imports, edit details/category and save, then use Looks good. Confirm the item leaves Review and remains in Transactions with its corrected details.
- In a month with purchases in multiple categories, tap a pie slice. Only its transactions should appear, while all slices and their proportions remain visible and other categories dim. Tap another slice directly, then a legend item/category row; selection and transactions should follow each tap. Reset filters to show all transactions. Repeat after changing months and using search/type filters.
- Enable app lock, background/reopen, authenticate with Face ID and passcode, cancel authentication, and disable the lock.
- Confirm storage errors display an actionable error screen, not a replacement empty ledger.
- In Settings → Appearance, switch through all ten themes and Follow system/Light/Dark. Check tab tint, controls, spending gradient, credit amounts, lock screen, and presented editors. Relaunch to confirm the choices persist. Verify the Home Screen icon shows ₹ after installing the update.

## Real-message imports

- Test at least one purchase and refund from HDFC, ICICI, and Axis, using anonymized fixtures with original formatting in tests as well.
- Test Visa and Mastercard alerts where available; verify account suffix, INR paise, merchant, date, and category.
- Test UPI debit, UPI credit, a transfer to your own account, and credit-card bill repayment. Correct own-account UPI payments to Transfer.
- Confirm OTPs, declines, collect requests, scheduled debits, and statement reminders do not become expenses.
- Test two genuine equal-amount purchases and a repeated notification. Check duplicate handling with and without references.
- Create the Shortcut, test in foreground, after force quitting, while locked, and after a restart/first unlock. Verify returned outcomes using a temporary notification action.
- With app lock enabled, verify background imports still persist without exposing the ledger UI.

## iCloud

- Use CloudDebug on both devices and the same Apple Account/container. Initial launch should seed a single visible copy of each default category after convergence.
- Add an expense on A and wait for it on B. Repeat with a category, rename, merchant rule, edit, and deletion.
- Go offline on A, import a transaction, reconnect, and verify it reaches B.
- Import the same SMS independently on both while offline. After syncing, verify one visible transaction and one contribution to totals.
- Delete an imported transaction, then retry its Shortcut. It should remain deleted, including after remote duplicate records arrive.
- Edit the same transaction/category on both offline devices. Review the converged result; SwiftData/CloudKit resolves same-record conflicts, while the app selects the newest logical duplicate deterministically.
- Test signed-out iCloud, unavailable network, account restrictions, and storage/quota errors without losing local data.
- Verify a fresh installation can restore records from the private database after sync. Keep an export before destructive testing.
- If distributing via TestFlight, deploy the schema to Production and repeat with CloudRelease; development records are separate.
