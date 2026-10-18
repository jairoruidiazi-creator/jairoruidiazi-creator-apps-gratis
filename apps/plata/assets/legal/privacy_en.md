# Plata privacy policy

Effective October 18, 2026.

## In short

Plata does not collect anyone's data. It has no accounts, ads, analytics or tracking tools, and we have no servers. Your accounts, transactions and budgets are stored encrypted, only on your phone. The app only connects to the internet to download exchange rates, and only if you use other currencies besides your main one.

## Who publishes the app

Plata is a free, open-source app published by the apps-gratis team under the developer name shown on its Google Play and App Store listings. The source code is at github.com/jairoruidiazi-creator/jairoruidiazi-creator-apps-gratis.

## What information the app handles and where it stays

- **Your finances:** accounts, balances, transactions, categories, budgets, scheduled payments, templates and notes.
- **Receipt photos** you attach to a transaction, taken with the camera or picked from your photos.
- **Bank notices (Android only, and only if you turn them on):** the title and text of notifications from the bank and wallet apps on the app's list, to suggest the transaction to you.
- **App settings**, the passcode (stored as a cryptographic hash, never in plain text) and automatic backups.

Everything lives on your phone, in the app's private folder. The data and receipt photos are stored encrypted with ChaCha20-Poly1305 and a key kept by the system (Android Keystore or iOS Keychain); if the phone does not offer that secure store, the key stays in the app's private folder. That folder is left out of Google and iCloud backups and of transfers to a new phone, because the key does not travel with it: to move your data to another phone, use the password-encrypted backup. Bank notices that arrive while the app is closed wait, unencrypted and briefly, in the app's private folder until you open it and Plata processes them. We do not receive any of this, see it or have any way to recover it.

## Permissions

- **Notification access (Android, optional):** only if you turn on bank notices. Plata reads only notifications from the bank and wallet apps on its list and ignores all others; what it reads is used on the phone. You can revoke the permission at any time in the system settings.
- **Camera and photos (optional):** to attach a photo of a receipt.
- **Fingerprint or face (optional):** to unlock the app; the system does the check and Plata does not receive your biometric data.
- **Notifications:** for your reminders to log expenses and to pay, which are scheduled on the phone.
- **Internet:** only for exchange rates (see below).

## What leaves the phone and to whom

If you use other currencies besides your main one and leave rate updates on, Plata checks once a day the official Colombian peso exchange rate (Tasa Representativa del Mercado) on datos.gov.co (Government of Colombia) and the European Central Bank reference rates through api.frankfurter.app and, as a fallback, open.er-api.com. These requests carry none of your data: those services only see the IP address the request comes from, like any website. Turn it off in More › Currencies.

The links in the guide (source code and report a problem) open the browser only if you tap them.

## Sharing and exporting

You decide when to export a CSV or Excel file, or make a backup (More › Backups). The encrypted backup is protected with the password you choose; the JSON backup (the app warns you first) and the CSV and Excel files are not encrypted. Backups hold your data, not receipt photos. Everything is shared with the system share sheet and is subject to the terms of whoever receives it; the app deletes its own copy of the file the next time you open it.

## Children

Plata is a personal finance tool for adults. It is not directed at children.

## Security

Besides encryption, you can set a passcode and unlock with fingerprint or face; after several failed attempts the wait between attempts grows. We recommend protecting the phone with a screen lock and keeping encrypted backups somewhere safe: if you lose the phone or the passcode, we cannot recover your data.

## Retention and deletion

Your data stays on the phone until you delete it. You can delete transactions, accounts and backups in the app, or delete everything by uninstalling it or clearing its data in the system settings. Backups you exported outside the app are deleted by you wherever you saved them. Since we keep no copies, there is nothing else to delete on our side.

## Your rights

Because we do not collect or keep personal data, we hold no information about you to access, correct or delete; you control it directly on the phone. This also covers the rights under Colombia's Law 1581 of 2012 and similar laws elsewhere.

## Changes to this policy

If the app changes how it handles information, we will update this policy and its effective date before publishing the new version. Previous versions remain in the repository history.

## Contact

Write to us by opening an issue at github.com/jairoruidiazi-creator/jairoruidiazi-creator-apps-gratis/issues or at the developer contact email shown on the app's store listing.
