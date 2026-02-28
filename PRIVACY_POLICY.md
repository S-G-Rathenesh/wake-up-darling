# Privacy Policy — Wake Up Darling

**Last Updated:** February 28, 2026

## Introduction

Wake Up Darling ("the App") is a couple bonding alarm application created by **S.G. Rathenesh**. This Privacy Policy explains how the App collects, uses, and protects your information.

By using the App, you agree to the terms outlined in this policy.

---

## Information We Collect

### 1. Account Information
- **Email address** and **display name** — collected via Firebase Authentication for account creation and login.
- **Profile photo** — optionally uploaded by users for personalization.

### 2. Couple & Pairing Data
- **Couple ID and partner association** — stored in Firebase Firestore to link paired users.

### 3. Chat Data
- **Text messages, voice notes, images, and videos** — exchanged between paired users within the App.
- **Message metadata** — timestamps, read/delivered status, reactions, and reply references.

### 4. Call Data
- **Call signaling metadata** — call type (voice/video), timestamps, duration, and connection status stored in Firestore.
- **WebRTC peer connection data** — used in real-time for voice and video calls; not permanently stored.

### 5. Alarm & Wake Data
- **Alarm schedules and statuses** — stored in Firestore to coordinate couple alarm functionality.
- **Voice wake recordings** — uploaded to Cloudinary and referenced in Firestore for the voice wake feature.
- **Wake statistics** — wake attempts, streaks, and alarm response data.

### 6. Device Information
- **Device token** — collected via Firebase Cloud Messaging for push notifications.
- **Timezone** — used to schedule alarms accurately.

---

## How We Use Your Information

| Purpose | Data Used |
|---|---|
| Account management & login | Email, display name |
| Couple pairing & features | Couple ID, partner info |
| Chat functionality | Messages, media, metadata |
| Voice & video calls | Call signaling, WebRTC streams |
| Alarm scheduling & wake features | Alarm data, voice recordings |
| Push notifications | Device token |
| Wake streaks & statistics | Alarm response data |

---

## Third-Party Services

The App uses the following third-party services:

| Service | Purpose | Privacy Policy |
|---|---|---|
| **Firebase** (Google) | Authentication, Firestore database, Cloud Messaging, Storage | [Firebase Privacy](https://firebase.google.com/support/privacy) |
| **Cloudinary** | Media storage (images, voice notes, voice wakes) | [Cloudinary Privacy](https://cloudinary.com/privacy) |
| **WebRTC** | Real-time voice and video communication | Peer-to-peer; no data stored by third parties |

---

## Data Storage & Security

- All user data is stored securely using **Firebase Firestore** with security rules that restrict access to authenticated and authorized users only.
- Media files are stored on **Cloudinary** using unsigned uploads scoped to the App.
- Voice and video call streams are transmitted **peer-to-peer** via WebRTC and are **not recorded or stored** by the App.
- Data is transmitted over **encrypted connections** (HTTPS/TLS).

---

## Data Sharing

We do **NOT**:
- Sell your personal data to any third party.
- Share your data with advertisers.
- Use your data for tracking or profiling beyond the App's functionality.

Your data is only accessible to:
- **You** and your **paired partner** within the App.
- **Firebase and Cloudinary** as infrastructure providers (subject to their own privacy policies).

---

## Data Retention & Deletion

- **Chat messages** — retained until deleted by users (delete for me / delete for everyone).
- **Account data** — retained as long as your account exists.
- **Alarm & wake data** — retained for streak tracking and statistics.
- **Account deletion** — you may request full deletion of your data by contacting the developer at the email below. Upon request, all associated data (Firestore records, Cloudinary media) will be permanently deleted.

---

## Permissions

The App may request the following device permissions:

| Permission | Purpose |
|---|---|
| **Microphone** | Voice calls, voice notes, voice wake recordings |
| **Camera** | Video calls, image capture for chat |
| **Notifications** | Push notifications for messages, calls, and alarms |
| **Exact Alarm** | Scheduling alarms at precise times |
| **Storage / Photos** | Sending and receiving media in chat |
| **Phone State** | Detecting active phone calls during alarms |

All permissions are requested at runtime and can be revoked through your device settings at any time.

---

## Children's Privacy

The App is not intended for use by anyone under the age of **13**. We do not knowingly collect information from children under 13. If you believe a child has provided us with personal data, please contact us for removal.

---

## Changes to This Policy

We may update this Privacy Policy from time to time. Changes will be reflected by updating the "Last Updated" date at the top of this document. Continued use of the App after changes constitutes acceptance of the updated policy.

---

## Contact

If you have questions, concerns, or data deletion requests, please contact:

**S.G. Rathenesh**  
Email: sgrathenesh@gmail.com  
GitHub: [github.com/S-G-Rathenesh](https://github.com/S-G-Rathenesh)

---

*This privacy policy applies to the Wake Up Darling mobile application.*
