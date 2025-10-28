# Product Overview

## Purpose

Nakama is an open-source server for social and real-time games and apps. This project extends Nakama to support MMORPG-grade features with Godot 4 client integration, focusing on:

- Large-scale persistent worlds with server-authoritative gameplay
- Seamless cross-region/shard player handoffs
- Live operations and content management tools
- Scalable economy and commerce systems

## Key Features

- **Authentication & Character Management**: Multi-character accounts with persistent state
- **Persistent Open World**: Server-authoritative zones with NPC AI, resource nodes, and environmental persistence
- **Instanced Content**: Party-based dungeons and arenas without matchmaking queues
- **Social Systems**: Guilds, parties, chat channels, friends, and moderation
- **Economy**: Transactional inventory, player trading, vendor systems, and item drops
- **Cross-Region Travel**: Seamless handoffs between zones/shards without relogging
- **Live-Ops Tools**: GM console, event scheduling, dynamic content deployment
- **Payments & Entitlements**: Server-validated purchases, durable cosmetics, wallet systems

## Objectives

- Support ≥50k CCU per shard, horizontally scalable to 1M+ CCU
- Maintain ≤150ms p95 latency for movement/combat within regions
- Achieve ≥99.9% weekly zone uptime with zero unplanned data loss
- Provide crash-safe persistence (RPO ≤5s, RTO ≤5min)
- Enable fair play through server-authoritative state validation

## Target Users

- **Players**: MMORPG gamers expecting responsive, persistent, and fair gameplay
- **Game Studios**: Development teams building large-scale multiplayer games with Godot
- **Live-Ops Teams**: Operators managing events, content updates, and player support
- **System Operators**: DevOps teams monitoring performance, deploying updates, and maintaining uptime
