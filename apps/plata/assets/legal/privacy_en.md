# Plata privacy policy

Effective October 18, 2026.

## In short

Plata does not collect anyone's data. It has no accounts, ads, analytics or tracking tools, and we have no servers. Your accounts, transactions and budgets are stored encrypted, only on your phone. The app only connects to the internet to download exchange rates, and only if you use other currencies besides your main one.

## Who publishes the app

Plata is a free, open-source app published by the apps-gratis team under the developer name shown on its Google Play and App Store listings. The source code is at github.com/jairoruidiazi-creator/jairoruidiazi-creator-apps-gratis.

## What information the app handles and where it stays

- **Your finances:** accounts, balances, transactions, categories, budgets, scheduled payments, templates and notes.
- **Receipt photos** you attach to a transaction, taken with the camera or picked from your photos.
- **Bank notices (Android only, and only if you turn them on):** the title and text of notifications from these bank and wallet apps, to suggest the transaction to you: Mi Bancolombia, Nequi, Daviplata, Davivienda, BBVA, Banco de Bogotá, Banco de Occidente, DAVIbank (formerly Scotiabank Colpatria), Lulo Bank, Nu and MOVii.
- **App settings**, the passcode (stored as a cryptographic hash, never in plain text) and automatic backups.

Everything lives on your phone, in the app's private folder. The data and receipt photos are stored encrypted with ChaCha20-Poly1305 and a key kept by the system (Android Keystore or iOS Keychain); if the phone does not offer that secure store when you install the app, the key stays in the app's private folder, protected by the system rather than by hardware. That folder is left out of Google and iCloud backups and of transfers to a new phone, because the key does not travel with it: to move your data to another phone, use the password-encrypted backup. Bank notices that arrive while the app is closed wait encrypted (AES-GCM, with an Android Keystore key) in the app's private folder until you open it and Plata processes them; if you turn notices off, they are deleted. On iPhone the Keychain keeps its keys even after you uninstall an app, so the first time Plata opens after being installed it deletes whatever a previous installation left behind, such as a passcode. We do not receive any of this, see it or have any way to recover it.

## Permissions

- **Notification access (Android, optional):** only if you turn on bank notices. Plata reads only notifications from the bank and wallet apps on its list and ignores all others; what it reads is used on the phone. If you turn notices off in Plata, it stops reading even while the permission is still granted; you can revoke the permission at any time in the system settings.
- **Camera and photos (optional):** to attach a photo of a receipt.
- **Fingerprint or face (optional):** to unlock the app; the system does the check and Plata does not receive your biometric data.
- **Notifications:** for your reminders to log expenses and to pay, which are scheduled on the phone. Plata asks for the permission the first time it is needed (when you save a scheduled item with a reminder or a card with a payment day, or turn on a reminder) and tells you why; under More › Settings you can see whether it is granted and grant it, and you can revoke it at any time in the system settings.
- **Internet:** only for exchange rates (see below).

## What leaves the phone and to whom

If you use other currencies besides your main one and leave rate updates on, Plata checks once a day the official Colombian peso exchange rate (Tasa Representativa del Mercado) on datos.gov.co (Government of Colombia), the European Central Bank reference rates through api.frankfurter.dev and, for currencies the European Central Bank does not publish, open.er-api.com (ExchangeRate-API). These requests carry none of your data: those services only see the IP address the request comes from, like any website. Turn it off in More › Currencies.

The links in the guide (source code and report a problem) open the browser only if you tap them.

## Sharing and exporting

You decide when to export a CSV or Excel file, or make a backup (More › Backups). The encrypted backup is protected with the password you choose; the JSON backup (the app warns you first) and the CSV and Excel files are not encrypted. Backups hold your data, not receipt photos. Everything is shared with the system share sheet and is subject to the terms of whoever receives it; the app deletes its own copy of the file, and the copy that the Android share sheet leaves in the app cache, the next time you open it and when you erase everything. When you restore, the temporary copy of the file you choose is deleted as soon as it is read.

## Children

Plata is a personal finance tool for adults. It is not directed at children.

## Security

Besides encryption, you can set a passcode and unlock with fingerprint or face; after several failed attempts the wait between attempts grows, even if you close the app. With a passcode, Plata covers itself when you leave it, so it does not show in recent apps, and Android does not allow screenshots of the app. With a passcode or with hidden balances, reminders show no amounts and Android hides them on the lock screen. Nobody can recover the passcode: if you forget it, the lock screen lets you erase everything Plata keeps on the phone and start over. We recommend protecting the phone with a screen lock and keeping encrypted backups somewhere safe: if you lose the phone or the passcode, we cannot recover your data.

## Retention and deletion

Your data stays on the phone until you delete it. You can delete transactions and accounts in the app; the automatic backups under More › Backups › Delete the automatic copies; and everything under More › Settings › Erase all data or with “Forgot the passcode?” on the lock screen, which remove data, photos, automatic backups, pending notices, the passcode and the encryption key; or uninstall it or clear its data in the system settings. Backups you exported outside the app are deleted by you wherever you saved them. Since we keep no copies, there is nothing else to delete on our side.

## Your rights

Because we do not collect or keep personal data, we hold no information about you to access, correct or delete; you control it directly on the phone. This also covers the rights under Colombia's Law 1581 of 2012 and similar laws elsewhere.

## Changes to this policy

If the app changes how it handles information, we will update this policy and its effective date before publishing the new version. Previous versions remain in the repository history.

## Contact

For any question, private ones included, use the support page: github.com/jairoruidiazi-creator/jairoruidiazi-creator-apps-gratis/blob/main/docs/SOPORTE.md. It explains how to open an issue at github.com/jairoruidiazi-creator/jairoruidiazi-creator-apps-gratis/issues and how to ask for private contact without posting personal data.
