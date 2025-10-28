# Technology Stack

## Server Runtime

- **Core**: Nakama server (Go-based)
- **Runtime Extensions**: TypeScript/Lua for custom game logic
- **Database**: PostgreSQL for persistent storage
- **Caching**: In-memory state management for active zones

## Client

- **Game Engine**: Godot 4
- **Language**: GDScript
- **Networking**: Nakama client SDK with WebSocket/gRPC support
- **Serialization**: JSON for RPCs, compressed binary for snapshots/deltas

## Infrastructure

- **Deployment**: Docker containers, Kubernetes orchestration
- **Networking**: TLS for transport security, JWT for authentication
- **Observability**: Prometheus metrics, Grafana dashboards, structured logging
- **CI/CD**: Blue/green deployments, canary releases, automated rollbacks

## Data Storage Schema

- **Accounts & Characters**: User profiles, character slots, metadata
- **World State**: Zone snapshots, entity positions, event logs
- **Social**: Guilds, friendships, chat history, moderation records
- **Economy**: Inventory, trade sessions, vendor catalogs, drop tables
- **Live-Ops**: Event schedules, script manifests, audit logs
- **Commerce**: Store catalogs, entitlements, wallet balances, purchase receipts

## Performance Targets

- Zone tick rate: 10-20 Hz
- Zone tick budget: ≤10ms at 1k active entities
- Database write latency: p95 ≤30ms
- Snapshot size: ≤512KB compressed
- Snapshot apply time: ≤50ms client-side
- Handoff duration: ≤1s for cross-region transfers
