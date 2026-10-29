#!/bin/bash
# Vercel build: installs Flutter and builds the web app.
# Set SUPABASE_URL and SUPABASE_ANON_KEY in the Vercel project's environment variables.
set -euo pipefail

if [ -z "${SUPABASE_URL:-}" ] || [ -z "${SUPABASE_ANON_KEY:-}" ]; then
  echo "ERROR: SUPABASE_URL and SUPABASE_ANON_KEY must be set" >&2
  exit 1
fi

if [ ! -d flutter ]; then
  git clone --depth 1 https://github.com/flutter/flutter.git -b stable
fi
export PATH="$PATH:$(pwd)/flutter/bin"

flutter --version
flutter config --no-analytics
flutter pub get
flutter build web --release \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"
