#!/usr/bin/env python3

import os
import re

# All constants to replace
CONSTANTS = [
    "kFallbackTileEstimateKb", "kPreviewTileZoom", "kPreviewTileY", "kPreviewTileX",
    "kDirectionConeHalfAngle", "kDirectionConeBaseLength", "kDirectionConeColor", "kDirectionConeOpacity",
    "kBottomButtonBarOffset", "kButtonBarHeight", "kAttributionSpacingAboveButtonBar",
    "kZoomIndicatorSpacingAboveButtonBar", "kScaleBarSpacingAboveButtonBar", "kZoomControlsSpacingAboveButtonBar",
    "kClientName", "kSuspectedLocationsCsvUrl", "kEnableDevelopmentModes", "kEnableNodeEdits", "kEnableNodeExtraction",
    "kNodeMinZoomLevel", "kOsmApiMinZoomLevel", "kMarkerTapTimeout", "kDebounceCameraRefresh",
    "kPreFetchAreaExpansionMultiplier", "kPreFetchZoomLevel", "kMaxPreFetchSplitDepth", "kDataRefreshIntervalSeconds",
    "kFollowMeAnimationDuration", "kMinSpeedForRotationMps", "kProximityAlertDefaultDistance",
    "kProximityAlertMinDistance", "kProximityAlertMaxDistance", "kProximityAlertCooldown",
    "kNodeDoubleTapZoomDelta", "kScrollWheelVelocity", "kPinchZoomThreshold", "kPinchMoveThreshold", "kRotationThreshold",
    "kTileFetchMaxAttempts", "kTileFetchInitialDelayMs", "kTileFetchBackoffMultiplier", "kTileFetchMaxDelayMs",
    "kTileFetchRandomJitterMs", "kMaxUserDownloadZoomSpan", "kMaxReasonableTileCount", "kAbsoluteMaxTileCount",
    "kAbsoluteMaxZoom", "kNodeIconDiameter", "kNodeDotOpacity", "kNodeRingColorReal", "kNodeRingColorMock",
    "kNodeRingColorPending", "kNodeRingColorEditing", "kNodeRingColorPendingEdit", "kNodeRingColorPendingDeletion",
    "kDirectionButtonMinWidth", "kDirectionButtonMinHeight"
]

def find_dart_files():
    """Find all .dart files except dev_config.dart"""
    dart_files = []
    for root, dirs, files in os.walk('.'):
        for file in files:
            if file.endswith('.dart'):
                path = os.path.join(root, file)
                if 'dev_config.dart' not in path:
                    dart_files.append(path)
    return dart_files

def process_file(filepath):
    """Process a single dart file"""
    print(f"  📝 Processing {filepath}")
    
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()
    except Exception as e:
        print(f"    ❌ Error reading file: {e}")
        return False
    
    original_content = content
    changes_made = []
    
    # Process each constant
    for constant in CONSTANTS:
        content, changed = process_constant_in_content(content, constant)
        if changed:
            changes_made.append(constant)
    
    # Only write if something actually changed
    if content != original_content:
        try:
            with open(filepath, 'w', encoding='utf-8') as f:
                f.write(content)
            print(f"    ✅ Updated: {', '.join(changes_made)}")
            return True
        except Exception as e:
            print(f"    ❌ Error writing file: {e}")
            return False
    else:
        print(f"    ⏭️  No changes needed")
        return False

def process_constant_in_content(content, constant):
    """Process a single constant in file content, handling const issues"""
    original_content = content
    
    # Skip if already using dev.constant (idempotent)
    if f"dev.{constant}" in content:
        return content, False
    
    # Skip if constant not found at all
    if constant not in content:
        return content, False
    
    print(f"    🔄 Replacing {constant}")
    
    # Pattern 1: const Type variable = kConstant;
    # Change to: final Type variable = dev.kConstant;
    pattern1 = rf'\bconst\s+(\w+)\s+(\w+)\s*=\s*{re.escape(constant)}\s*;'
    replacement1 = rf'final \1 \2 = dev.{constant};'
    content = re.sub(pattern1, replacement1, content)
    
    # Pattern 2: static const Type variable = kConstant;
    # Change to: static final Type variable = dev.kConstant;
    pattern2 = rf'\bstatic\s+const\s+(\w+)\s+(\w+)\s*=\s*{re.escape(constant)}\s*;'
    replacement2 = rf'static final \1 \2 = dev.{constant};'
    content = re.sub(pattern2, replacement2, content)
    
    # Pattern 3: const ConstructorName(...kConstant...)
    # We need to be careful here - find const constructors that contain our constant
    # and remove the const keyword
    # This is tricky to do perfectly with regex, so let's do a simple approach:
    # If we find "const SomeConstructor(" followed by our constant somewhere before the matching ")"
    # we'll remove the const keyword from the constructor
    
    # Find all const constructor calls that contain our constant
    const_constructor_pattern = r'\bconst\s+(\w+)\s*\([^)]*' + re.escape(constant) + r'[^)]*\)'
    matches = list(re.finditer(const_constructor_pattern, content))
    
    # Replace const with just the constructor name for each match
    for match in reversed(matches):  # Reverse to maintain positions
        full_match = match.group(0)
        constructor_name = match.group(1)
        # Remove 'const ' from the beginning
        replacement = full_match.replace(f'const {constructor_name}', constructor_name, 1)
        content = content[:match.start()] + replacement + content[match.end():]
    
    # Pattern 4: Simple replacements - any remaining instances of kConstant
    # Use word boundaries to avoid partial matches, but avoid already replaced dev.kConstant
    pattern4 = rf'\b{re.escape(constant)}\b(?![\w.])'  # Negative lookahead to avoid partial matches
    replacement4 = f'dev.{constant}'
    content = re.sub(pattern4, replacement4, content)
    
    return content, content != original_content

def main():
    print("🚀 Starting dev_config reference update...")
    print("🔍 Finding Dart files...")
    
    dart_files = find_dart_files()
    print(f"📁 Found {len(dart_files)} Dart files to process")
    
    if not dart_files:
        print("❌ No Dart files found!")
        return
    
    updated_files = 0
    
    for filepath in dart_files:
        if process_file(filepath):
            updated_files += 1
    
    print(f"\n✨ Finished! Updated {updated_files} out of {len(dart_files)} files")
    print("💡 Next steps:")
    print("   1. flutter analyze (check for syntax errors)")
    print("   2. flutter pub get (refresh dependencies)")
    print("   3. flutter run (test the app)")
    
    if updated_files > 0:
        print("⚠️  If you see compilation errors, the script can be run again safely")

if __name__ == '__main__':
    main()