# PixelMagic AI

Flutter Android starter for PixelMagic AI.

## Current status
- Dark-themed Flutter app shell
- Email/password sign-up and sign-in connected to the PixelMagic AI Supabase project
- Home screen with planned creative-tool entry points
- AI generation, photo editing, video tools, Google sign-in, subscriptions and billing are not implemented yet
- Supabase database is provisioned separately with row-level security; no service-role key is included here

## Build APK
Open **Actions** → **Build Android APK** → **Run workflow**. The workflow generates the Android platform files, runs Dart analysis, builds a debug APK, and uploads it as an artifact.

The workflow uses the Supabase **publishable** client key. This key is designed for client applications and is not a service-role secret. Never add a Supabase secret/service-role key to this repository or an Android app.
