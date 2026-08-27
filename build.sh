#!/bin/bash

echo "Downloading Flutter..."
git clone https://github.com/flutter/flutter.git -b stable

echo "Adding Flutter to PATH..."
export PATH="$PATH:`pwd`/flutter/bin"

echo "Checking Flutter version..."
flutter --version

echo "Building Flutter Web..."
flutter build web --release
