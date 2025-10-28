# Character Service Module

TypeScript runtime module for MMORPG character management.

## Responsibilities

- List characters for authenticated accounts (Requirement 2)
- Create new characters with validation (Requirement 3)
- Load character state for world entry
- Enforce character slot limits
- Validate character names (length, profanity)

## RPC Endpoints

Implemented in subsequent tasks:

- `list_characters` - Query characters by account_id (Task 1.3.2)
- `create_character` - Create new character with validation (Task 1.3.3)
- `select_character` - Load character state for world entry (Task 1.3.4)
- Character name validation helper (Task 1.3.5)

## Data Models

See `character.ts` for TypeScript interface definitions:
- `Character` - Basic character data
- `CharacterState` - Full character state with inventory, stats, etc.

## Database Schema

Characters are stored in the `characters` table (migration in `migrate/sql/`).
