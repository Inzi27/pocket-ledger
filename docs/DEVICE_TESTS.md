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
# Usability enhancements — October 2026

Use a test ledger or export existing data first. Updating via Xcode with the same bundle identifier should retain the existing ledger.

1. In Settings → Complete backup & restore, export a JSON backup. Cancel an export first and confirm the last-export date is unchanged. After a successful export, confirm the timestamp updates. Turn on weekly in-app reminders.
2. Restore the backup and confirm existing transactions are not duplicated. In a test ledger, delete one transaction and restore it; confirm its details and import-history link return. Repeat deletion/restoration. Restore onto a fresh test install and confirm renamed/default and unused/archived categories, merchant rules, budgets, payment nicknames, and import history.
3. Paste a valid bank message, duplicate, OTP, and unknown format. Saved transactions close the sheet; other results remain visible with the input intact. Import activity shows each result and source. Run the existing Shortcut to confirm its timestamp and linked result. No historical or missed-automation events should be fabricated.
4. Edit a saved import's category, reimport the original message, and confirm the edit remains. Open Review with a flagged transaction in an older month: it should appear under All time and match the badge.
5. Select an older month on Overview, then See all and Cards & payments; each should preserve that month. Tap the month to jump across years. Check date ranges include transactions late on the Through date. Collapse/reopen the pie and confirm selection still toggles without removing other slices.
6. Name a card, find it by nickname, filter by card/bank/UPI, and clear filters without changing dates. Card spending must exclude repayments/transfers and subtract refunds. Cards with identical last four digits at different banks remain distinct. Check compact/large Dynamic Type layouts.
7. Open an existing monthly budget without editing: Save should be disabled. Editing then saving should retain the new amount; deliberately blanking the amount should remove that budget.
