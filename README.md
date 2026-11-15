# PixelMagic AI

Flutter Android starter for PixelMagic AI.

## Current status
- Flutter app shell and dark UI
- Email/password sign-in and sign-up through Supabase once the publishable key is configured
- Feature tiles are placeholders; AI generation, editing, video tools, subscriptions and billing are not implemented yet
- Supabase database is provisioned separately; never put a service-role key in this repository

## Build APK
Open **Actions** → **Build Android APK** → **Run workflow**. The workflow builds a debug APK and uploads it as an artifact.

The Supabase publishable key is intentionally not committed. Later, add it as a GitHub Actions repository secret named `SUPABASE_PUBLISHABLE_KEY` and pass it to Flutter using `--dart-define`. Do not add a Supabase secret/service-role key.
