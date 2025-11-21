#!/bin/bash

# Super simple test - just replace one constant first
echo "🔄 Testing with kClientName..."

find . -name "*.dart" -not -path "./lib/dev_config.dart" -exec grep -l "kClientName" {} \;

echo "Found files with kClientName. Now replacing..."

find . -name "*.dart" -not -path "./lib/dev_config.dart" -exec sed -i '' 's/kClientName/dev.kClientName/g' {} \;

echo "✅ Done with test. Check if lib/services/uploader.dart changed"