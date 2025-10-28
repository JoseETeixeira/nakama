# MMORPG Nakama Godot Client

Godot 4 client for MMORPG-grade Nakama server integration (2D top-down game).

## Project Structure

This Godot 4 project implements the client-side logic for connecting to the MMORPG Nakama server. The client is built as a **2D top-down game** to demonstrate the server's dimension-agnostic capabilities.

### Autoload Singletons

- **NakamaManager** (`autoload/NakamaManager.gd`)
  - Manages Nakama client connections
  - Handles authentication (device ID)
  - Provides RPC methods for character management
  - Manages world entry and zone streaming

- **WorldState** (`autoload/WorldState.gd`)
  - Maintains client-side world state (2D entities)
  - Handles snapshot decompression and application
  - Processes delta updates from server
  - Manages entity spawning/despawning (Node2D instances)

### Scene Hierarchy

- **scenes/auth/**
  - `LoginScreen.tscn` - Device authentication UI
  - `CharacterSelect.tscn` - Character selection and creation UI

- **scenes/world/**
  - `Zone.tscn` - Main game world scene (2D top-down view with Camera2D)
  - (Additional scenes for Player, NPCs, etc. will be added in later tasks)

## Development Tasks

### Phase 1: Foundation (Current)

- [x] **Task 1.4.1** - Set up Godot 4 project structure
  - Created autoload singletons (NakamaManager, WorldState)
  - Set up scene hierarchy (auth, character_select, world)

- [x] **Task 1.4.2** - Install nakama-godot plugin
  - Installed plugin to `addons/com.heroiclabs.nakama/`
  - Added Nakama autoload to project
  - Configured server connection via Project Settings (nakama/server/*)
  - Updated NakamaManager to use configurable settings
  - See `NAKAMA_SETUP.md` for configuration details

- [ ] **Task 1.4.3** - Implement authentication screen
- [ ] **Task 1.4.4** - Implement character selection screen
- [ ] **Task 1.4.5** - Implement character creation flow
- [ ] **Task 1.4.6** - Implement character selection flow

### Phase 2: World Entry

- World entry RPC integration
- Zone snapshot loading
- Delta stream subscription
- Entity rendering

## Requirements

- Godot 4.3+
- nakama-godot plugin (installed in `addons/com.heroiclabs.nakama/`)

## Server Integration

This client connects to the Nakama MMORPG server located in the parent directory.

### Default Configuration

Configuration is managed via **Project Settings → Nakama → Server**:

- **Server Host**: 127.0.0.1
- **Server Port**: 7350
- **Server Protocol**: HTTP
- **Server Key**: defaultkey

To modify these settings, edit `project.godot` or use the Godot editor's Project Settings panel. See `NAKAMA_SETUP.md` for detailed configuration instructions.

## Running the Project

1. Open the project in Godot 4.3+
2. Ensure the Nakama server is running on localhost:7350
   ```powershell
   # From repository root
   docker compose up
   ```
3. Run the project (F5)
4. Click "Login with Device ID" to authenticate
5. Create or select a character to enter the world

**Note:** Task 1.4.3 (authentication screen) is not yet implemented. The current project structure is ready for UI implementation.

## Architecture

The client follows the design specified in:
- `.kiro/specs/mmorpg-nakama-godot/design.md` (Section: Client Integration)
- `.kiro/specs/mmorpg-nakama-godot/requirements.md` (Requirements 1-6)

### Key Features

- **Server-Authoritative**: All gameplay logic validated server-side
- **Client Prediction**: Responsive movement with server reconciliation (Phase 3)
- **Snapshot/Delta Model**: Efficient world state synchronization
- **AOI Management**: Only render entities in Area of Interest
- **Seamless Handoffs**: Cross-zone travel without disconnection (Phase 6)

## Next Steps

1. ~~Install nakama-godot plugin (Task 1.4.2)~~ ✅ **Completed**
2. Implement authentication flow (Task 1.4.3)
3. Build character selection UI (Task 1.4.4-1.4.6)
4. Integrate world entry and snapshot loading (Phase 2)

## Configuration Documentation

See `NAKAMA_SETUP.md` for detailed information about:
- Plugin installation and structure
- Server configuration via Project Settings
- Usage examples for authentication and character management
- Troubleshooting common connection issues

## License

MIT License - See LICENSE file in parent directory
