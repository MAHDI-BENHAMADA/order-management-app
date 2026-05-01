# Order Tracking Dashboard

A mobile-first Flutter app for sellers to manage and track orders directly from Google Sheets.

## Features

- ✅ Google Sign-In authentication
- 📊 Real-time order tracking from Google Sheets
- 🇸🇦 Arabic RTL interface
- 📞 One-tap phone dialer integration
- 📋 Current Orders & Archive tabs
- 🔄 Live status updates (confirm, canceled, no_response, uploaded)

## Prerequisites

- Flutter SDK (^3.11.4)
- Google Firebase project with Google Sheets API enabled
- Android device/emulator

## Setup

### 1. Firebase & Google Cloud Setup
1. Create a Firebase project at [console.firebase.google.com](https://console.firebase.google.com)
2. Add an Android app and download `google-services.json`
3. Place `google-services.json` in `android/app/`
4. Enable Google Sheets API: https://console.developers.google.com/apis/api/sheets.googleapis.com/overview
5. Get your debug SHA-1 key: `cd android && ./gradlew signingReport`
6. Add the SHA-1 fingerprint to Firebase Console > Project Settings > Android app
7. Add your test email to OAuth consent screen > Test users

### 2. Install Dependencies
```bash
flutter pub get
```

### 3. Configure Firebase Functions
If you want the app to keep auto-sharing selected sheets without shipping credentials in the APK, configure the backend email lookup:
```bash
cd functions
npm install
firebase functions:config:set app.service_account_email="YOUR_SERVICE_ACCOUNT_EMAIL"
firebase deploy --only functions
```

### 4. Run the App
```bash
flutter run
```

## How to Use

1. **Sign In:** Click "Sign in with Google" and authenticate
2. **Add Sheet:** Paste your Google Sheet URL (app auto-extracts the Sheet ID)
3. **Track Orders:** View current orders or archived orders
4. **Update Status:** Tap status buttons to change order status in real-time
5. **Call:** Tap the phone icon to dial the customer

## Tech Stack

- **Framework:** Flutter (Dart)
- **Backend:** Google Sheets API v4
- **Auth:** Google Sign-In
- **Storage:** Shared Preferences
- **UI:** Material Design with Arabic localization
