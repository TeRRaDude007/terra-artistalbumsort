This script automatically organizes music releases from an unsorted directory into a structured archive based on artist names. It supports optional recursive scanning of subdirectories and handles special cases like various artists (VA), DJ/Van artists, and numeric artist names.

Key Features:
Artist Extraction: Detects the artist from the folder/release name.
Handles special cases like VA, VariousArtiest, DJ_Artist, Van_Artist, and numeric artist names.
Artist Normalization: Converts names to CamelCase with underscores.
Removes unwanted suffixes such as Ft, Feat, Featuring, VS, Presents, With, etc.
Directory Mapping: Alphabetical mapping: /BASE_DIR/<first_letter>/<Artist_Name>/.
Numeric artists: optionally moved to /BASE_DIR/0-9/<Artist_Name>/.
VA / Various Artists: moved to /BASE_DIR/VA/ or /BASE_DIR/VariousArtiest/ based on the setting.
Duplicate Handling: If a release already exists in the target folder, it is moved to a duplicates directory (DUPLICATES).

Sandbox Mode:
If enabled, the script only logs preview moves without actually moving files.
Logs all actions in MUSICSORTARCH.log including preview moves.
Recursive Scanning (Optional): Can scan all subdirectories under the unsorted directory, allowing organization of releases stored in dated or subcategory folders.

Addon:
- Case-insensitive artist matching.
- Treat dots, spaces and underscores as equivalent.
- Reuse an existing artist directory with its original spelling.
- Create missing artist directories using canonical title-case names.
- Handle _-_, normal hyphens, three-digit artist prefixes, _And_, and existing artist prefixes.
- Rename duplicate album directories rather than skipping or overwriting them.
- Keep category scopes separate.
- Use SANDBOX_MODE for testing.
