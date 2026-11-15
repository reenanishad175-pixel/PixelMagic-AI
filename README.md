# PixelMagic AI

Flutter Android app for the PixelMagic AI project.

## Implemented in the current test build
- Email/password registration with name and Indian mobile number.
- Email verification through the Supabase confirmation link.
- Login using email + password or mobile number + the same password.
- Database-enforced unique mobile numbers and unique email addresses.
- Google OAuth sign-in button; after Google sign-in, the app asks the user to add a mobile number if the profile does not have one.
- Forgot-password email link and an in-app screen for setting a new password.
- User profile and credit-balance display with row-level security.

## Still requires owner-side setup
- Google OAuth client ID and client secret must be added to Google Cloud and the Supabase Google provider settings. The app cannot complete Google OAuth until these credentials are configured.
- AI image/video generation and photo-editing providers are not connected. The creative-tool screens currently let the user choose a photo and prepare a prompt, but do not generate/export media.
- Phone numbers are not OTP-verified. The app enforces uniqueness, but because no phone OTP is used, it cannot prove that the number belongs to the person who entered it.

## Build APK
Open **Actions** → **Build Android APK** → **Run workflow**. The workflow generates the Android platform files, runs Dart analysis, builds a debug APK, and uploads it as the `PixelMagic-AI-debug-apk` artifact.

The workflow uses the Supabase **publishable** client key. This key is designed for client applications. Never add a Supabase secret/service-role key to this repository or an Android app.
