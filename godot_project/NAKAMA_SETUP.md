# Nakama-Godot Plugin Setup

**Task:** 1.4.2 - Install nakama-godot plugin
**Completed:** October 28, 2025

## Installation

The nakama-godot plugin has been installed in this project at:
```
godot_project/addons/com.heroiclabs.nakama/
```

### Plugin Structure

```
addons/com.heroiclabs.nakama/
├── Nakama.gd          # Main plugin autoload
├── Satori.gd          # Satori analytics integration
├── api/               # REST API client
├── client/            # HTTP client implementation
├── socket/            # WebSocket real-time communication
└── utils/             # Utility classes
```

## Configuration

The Nakama server connection is configured via **Project Settings** under the `nakama/server/` section:

### Project Settings (project.godot)

```ini
[nakama]

server/host="127.0.0.1"        # Nakama server hostname
server/port=7350               # Nakama HTTP port
server/protocol="http"         # Protocol (http or https)
server/key="defaultkey"        # Server API key
```

### Autoloads

The following singletons are automatically loaded when the project starts:

1. **Nakama** (`res://addons/com.heroiclabs.nakama/Nakama.gd`)
   - Core plugin singleton providing `Nakama.create_client()` and `Nakama.create_socket_from()`

2. **NakamaManager** (`res://autoload/NakamaManager.gd`)
   - Project-specific wrapper for Nakama operations
   - Reads configuration from Project Settings
   - Provides RPCs for authentication, characters, world entry

3. **WorldState** (`res://autoload/WorldState.gd`)
   - Manages client-side world state and entity synchronization

## Usage

### Basic Authentication Example

```gdscript
# Authenticate with device ID
await NakamaManager.authenticate_device()

# Session is now available
print("User ID: ", NakamaManager.session.user_id)
```

### Character Management

```gdscript
# List characters for this account
var characters = await NakamaManager.list_characters()
for character in characters:
    print("Character: ", character["name"])

# Create a new character
var character_id = await NakamaManager.create_character("HeroName", "warrior")
print("Created character: ", character_id)
```

### Changing Server Configuration

You can override the default configuration in two ways:

#### Option 1: Edit Project Settings

1. Open **Project → Project Settings**
2. Navigate to **Nakama → Server**
3. Modify host, port, protocol, or key
4. Restart the project

#### Option 2: Edit project.godot Directly

Open `project.godot` and modify the `[nakama]` section:

```ini
[nakama]

server/host="production.example.com"
server/port=7350
server/protocol="https"
server/key="your-production-key"
```

## Development Workflow

### Local Development

The default configuration points to `localhost:7350` which matches the Docker Compose setup in the parent directory.

**Start the Nakama server:**

```powershell
# From repository root
docker compose up
```

**Verify the server is running:**

- Console: http://localhost:7351 (admin/password)
- HTTP API: http://localhost:7350
- gRPC API: localhost:7349

### Testing Connection

Run the Godot project and check the console output:

```
[NakamaManager] Initializing Nakama client...
[NakamaManager] Server config: http://127.0.0.1:7350 (key: defaultkey)
[NakamaManager] Nakama client initialized
```

If authentication succeeds:
```
[NakamaManager] Authenticated: <user_id>
[NakamaManager] Socket connected
```

## Troubleshooting

### Error: "Connection refused"

**Problem:** Nakama server is not running or not accessible.

**Solution:**
1. Verify the Docker Compose stack is running: `docker compose ps`
2. Check if port 7350 is accessible: `curl http://localhost:7350`
3. Verify the `server/host` and `server/port` in Project Settings

### Error: "Invalid API key"

**Problem:** The `server/key` doesn't match the Nakama server configuration.

**Solution:**
1. Check the server key in `docker-compose.yml` (should be `defaultkey` for local dev)
2. Update Project Settings → Nakama → Server → Key

### Error: "Nakama singleton not found"

**Problem:** The plugin autoload is not configured correctly.

**Solution:**
1. Verify `addons/com.heroiclabs.nakama/Nakama.gd` exists
2. Check **Project → Project Settings → Autoload** shows `Nakama` singleton
3. Restart Godot editor

## Requirements Satisfied

This task satisfies the following requirements:

- **Requirement 1** (Player Authentication) - Plugin provides authentication methods
- **Requirement 2** (Character List/Selection) - Client can call character RPCs via plugin
- **Requirement 3** (Character Creation) - Plugin enables RPC calls for character creation
- **Requirement 4** (World Entry) - Socket streaming capabilities for zone updates

## Next Steps

### Task 1.4.3: Implement Authentication Screen

Create UI for device login using:
```gdscript
await NakamaManager.authenticate_device()
```

### Task 1.4.4: Implement Character Selection Screen

Build character list UI and call:
```gdscript
var characters = await NakamaManager.list_characters()
```

## References

- **nakama-godot Repository:** https://github.com/heroiclabs/nakama-godot
- **Nakama Documentation:** https://heroiclabs.com/docs
- **Design Document:** `.kiro/specs/mmorpg-nakama-godot/design.md` (Section: Client Integration)
- **Requirements:** `.kiro/specs/mmorpg-nakama-godot/requirements.md` (Requirements 1-6)

## Version Information

- **Plugin Version:** Latest (cloned October 28, 2025)
- **Godot Version:** 4.3
- **Nakama Server Version:** 3.30.0 (local-dev build)
- **Task Completion Date:** October 28, 2025
