# DeFlock Localizations

This directory contains translation files for DeFlock. Each language is a simple JSON file.

## Adding a New Language

Want to add support for your language? It's simple:

1. **Copy the English file**: `cp en.json your_language_code.json`
   - Use 2-letter language codes: `es` (Spanish), `fr` (French), `it` (Italian), etc.

2. **Edit your new file**:
   ```json
   {
     "language": {
       "name": "Your Language Name"  ← Change this to your language in your language
     },
     "app": {
       "title": "DeFlock"  ← Keep this as-is
     },
     "actions": {
       "tagNode": "Your Translation Here",
       "download": "Your Translation Here",
       ...
     }
   }
   ```

3. **Add your language to the About screen**: Edit `assets/info.txt` and add your language section at the bottom (copy the English section and translate it)

4. **Submit a PR** with your JSON file and the updated about.txt. Done!

The new language will automatically appear in Settings → Language.

## Translation Rules

- **Only translate the values** (text after the `:`), never the keys
- **Keep `{}` placeholders** if you see them - they get replaced with numbers/text
- **Don't translate "DeFlock"** - it's the app name
- **Use your language's name for itself** - "Français" not "French", "Español" not "Spanish"

## Current Languages

- `en.json` - English
- `es.json` - Español 
- `fr.json` - Français
- `de.json` - Deutsch

## Files to Update

For a complete translation, you'll need to touch:
1. **`lib/localizations/xx.json`** - Main UI translations (buttons, menus, etc.)
2. **`assets/info.txt`** - About screen content (add your language section)

## That's It!

No configuration files, no build steps, no complex setup. Add your files and it works.