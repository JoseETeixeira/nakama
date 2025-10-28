# Project Structure

## File Organization

```
nakama/
├── server/                 # Core Nakama server code (Go)
│   ├── api_*.go           # API endpoint handlers
│   ├── core_*.go          # Core business logic
│   ├── console_*.go       # Admin console handlers
│   └── config.go          # Configuration management
├── data/modules/          # Runtime modules (TypeScript/Lua)
│   ├── character/         # Character management RPCs
│   ├── world/             # World state, zones, snapshots
│   ├── combat/            # Server-authoritative combat logic
│   ├── social/            # Guilds, chat, friends
│   ├── economy/           # Inventory, trading, vendors
│   ├── instance/          # Dungeon/arena instance management
│   ├── handoff/           # Cross-region transfer logic
│   ├── liveops/           # GM tools, event scheduler
│   └── commerce/          # Store, purchases, entitlements
├── migrate/sql/           # Database migrations
├── .kiro/
│   ├── steering/          # Project-wide guidance
│   └── specs/             # Feature specifications
│       └── mmorpg-nakama-godot/
│           ├── requirements.md
│           ├── design.md
│           └── tasks.md
├── build/                 # Build scripts, Dockerfiles
└── sample_go_module/      # Example module implementations
```

## Conventions

- **Server Code**: Follow Go conventions, idiomatic error handling
- **Runtime Modules**: Typed interfaces for RPC signatures; comprehensive JSDoc/LuaDoc
- **Database**: Migrations are versioned; all schema changes go through migration files
- **Testing**: Unit tests for server logic, integration tests for RPC flows, load tests for scalability
- **Naming**:
  - RPCs: `snake_case` (e.g., `list_characters`, `zone_snapshot`)
  - Database tables: `snake_case` (e.g., `world_state`, `handoff_tokens`)
  - TypeScript/Lua functions: `camelCase` (e.g., `enterWorld`, `applySnapshot`)
  - GDScript: `snake_case` for functions, `PascalCase` for classes

## Development Workflow

1. Spec-driven: Requirements → Design → Tasks → Implementation
2. Feature branches with PR reviews
3. Automated testing before merge
4. Canary deployments to production with rollback capability
