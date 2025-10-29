# MMORPG Loot System - Database Schema

## Overview

The loot system uses a relational database approach to define what items drop from NPCs, bosses, and resource nodes. This provides:

- **Server-authoritative** drop rate control
- **Real-time balancing** via database updates (no code deployment)
- **Analytics-friendly** structure for drop rate tracking
- **Nested drop tables** for rare loot mechanics

## Database Schema

### `drop_tables` Table

Defines named drop table configurations.

| Column | Type | Description |
|--------|------|-------------|
| drop_table_id | VARCHAR(100) PK | Unique identifier (e.g., "goblin_common") |
| description | TEXT | Human-readable description |
| entity_type | VARCHAR(50) | Type: 'npc', 'boss', 'resource_node', 'chest' |
| drop_policy | VARCHAR(50) | Policy: 'per_killer' or 'shared_party' |
| metadata | JSONB | Additional config (level range, zone restrictions) |
| created_at | TIMESTAMPTZ | Creation timestamp |
| updated_at | TIMESTAMPTZ | Last update timestamp |

### `drop_table_items` Table

Defines items that can drop from drop tables with probabilities.

| Column | Type | Description |
|--------|------|-------------|
| id | SERIAL PK | Auto-increment primary key |
| drop_table_id | VARCHAR(100) FK | Reference to drop_tables |
| item_id | VARCHAR(100) | Item template ID (XOR with nested_table_id) |
| nested_table_id | VARCHAR(100) FK | Nested drop table for rare loot (XOR with item_id) |
| drop_chance | DECIMAL(5,4) | Probability 0.0-1.0 (independent rolls) |
| quantity_min | INT | Minimum quantity if drop succeeds |
| quantity_max | INT | Maximum quantity (RNG between min/max) |
| is_guaranteed | BOOLEAN | TRUE for boss guaranteed drops |
| metadata | JSONB | Item-specific metadata (rarity, stats, description) |
| created_at | TIMESTAMPTZ | Creation timestamp |

**Constraints:**
- `item_id` and `nested_table_id` are mutually exclusive (CHECK constraint)
- `drop_chance` must be between 0.0 and 1.0
- `quantity_min` must be > 0
- `quantity_max` must be >= `quantity_min`

## Drop Policies

### `per_killer`
Each player who participated in the kill gets independent loot rolls.

**Example:** In a 5-player party killing a goblin:
- Each player rolls the drop table independently
- Player 1 might get gold + potion
- Player 2 might get only gold
- Different loot for each player

### `shared_party`
Loot is rolled once and shared/distributed among party members.

**Example:** In a 5-player party killing a boss:
- Boss loot is rolled once
- Results are shared (e.g., round-robin, need/greed, leader decides)
- Same loot pool for all players

## Nested Drop Tables

Drop tables can reference other drop tables for rare loot mechanics.

**Example Flow:**
1. Player kills elite goblin
2. Server rolls `elite_goblin` drop table
3. One entry has `nested_table_id = 'rare_goblin_loot'` with `drop_chance = 0.02` (2%)
4. If RNG succeeds, server recursively rolls `rare_goblin_loot` table
5. Results from nested table are added to final loot

**Use Cases:**
- Rare drops from elite enemies
- Legendary drops from bosses
- Bonus loot from special conditions

## Guaranteed Drops

Boss encounters can have guaranteed drops using `is_guaranteed = TRUE`.

**Behavior:**
- `drop_chance` is ignored
- Item always drops
- Quantity still uses RNG between `quantity_min` and `quantity_max`

**Example:**
```sql
INSERT INTO drop_table_items (drop_table_id, item_id, drop_chance, quantity_min, quantity_max, is_guaranteed)
VALUES ('boss_dragon', 'dragon_scale', 1.0, 3, 5, TRUE);
```
- Boss always drops 3-5 dragon scales (guaranteed)
- Gold, potions, etc. are RNG-based (not guaranteed)

## Example Drop Tables

### Simple NPC: Goblin Common
```
drop_table_id: goblin_common
entity_type: npc
drop_policy: per_killer

Items:
- gold_coins (100% chance, 5-15 qty)
- goblin_ear (30% chance, 1 qty)
- potion_health_minor (15% chance, 1-2 qty)
- rusty_dagger (5% chance, 1 qty)
```

### Elite NPC with Nested Table: Elite Goblin
```
drop_table_id: elite_goblin
entity_type: npc
drop_policy: per_killer

Items:
- gold_coins (100% chance, 25-50 qty)
- goblin_ear (50% chance, 1-2 qty)
- potion_health_greater (25% chance, 1-3 qty)
- steel_shortsword (10% chance, 1 qty)
- nested: rare_goblin_loot (2% chance)
```

### Boss with Guaranteed Drops: Dragon
```
drop_table_id: boss_dragon
entity_type: boss
drop_policy: shared_party

Guaranteed:
- dragon_scale (3-5 qty, always)
- gold_coins (500-1000 qty, always)

Items:
- dragon_fang (50% chance, 1-2 qty)
- legendary_weapon_fragment (15% chance, 1 qty)
- potion_resurrection (30% chance, 1-3 qty)
- nested: dragon_legendary_loot (5% chance)
```

### Resource Node: Iron Ore
```
drop_table_id: resource_iron_ore
entity_type: resource_node
drop_policy: per_gatherer

Items:
- iron_ore (100% chance, 1-3 qty)
- rough_stone (40% chance, 1-2 qty)
- iron_ore_rich (10% chance, 1 qty)
- uncut_gem (2% chance, 1 qty)
```

## Usage in Game Code

### 1. Query Drop Table
```typescript
const result = await nk.sqlQuery(`
  SELECT dt.*, dti.*
  FROM drop_tables dt
  JOIN drop_table_items dti ON dt.drop_table_id = dti.drop_table_id
  WHERE dt.drop_table_id = $1
`, [dropTableId]);
```

### 2. Roll Drops (Server-Side RNG)
```typescript
function rollDrops(dropTableItems, seed) {
  const loot = [];
  const rng = seededRandom(seed);

  for (const item of dropTableItems) {
    if (item.is_guaranteed || rng() <= item.drop_chance) {
      const qty = randomInt(item.quantity_min, item.quantity_max, rng);

      if (item.nested_table_id) {
        // Recursively resolve nested table
        const nestedLoot = generateLoot(item.nested_table_id, seed);
        loot.push(...nestedLoot);
      } else {
        loot.push({ item_id: item.item_id, quantity: qty });
      }
    }
  }

  return loot;
}
```

### 3. Log to Analytics
```typescript
await nk.sqlExec(`
  INSERT INTO event_log (event_type, entity_id, metadata)
  VALUES ('loot_drop', $1, $2)
`, [npcId, JSON.stringify({
  drop_table_id: dropTableId,
  items: loot,
  player_id: playerId,
  seed: seed
})]);
```

## Balancing & Analytics

### Drop Rate Queries

**Total drops per item:**
```sql
SELECT
  metadata->>'item_id' as item_id,
  COUNT(*) as drop_count
FROM event_log
WHERE event_type = 'loot_drop'
  AND created_at > NOW() - INTERVAL '7 days'
GROUP BY metadata->>'item_id'
ORDER BY drop_count DESC;
```

**Drop rate by NPC type:**
```sql
SELECT
  entity_id as npc_type,
  metadata->>'drop_table_id' as drop_table,
  COUNT(*) as kills,
  SUM((metadata->'items')::jsonb ? 'rare_item') as rare_drops,
  ROUND(SUM((metadata->'items')::jsonb ? 'rare_item')::int * 100.0 / COUNT(*), 2) as rare_drop_rate_pct
FROM event_log
WHERE event_type = 'loot_drop'
GROUP BY entity_id, metadata->>'drop_table_id';
```

### Live Tuning

Update drop rates without code deployment:

```sql
-- Increase rare drop chance from 2% to 5%
UPDATE drop_table_items
SET drop_chance = 0.05
WHERE drop_table_id = 'elite_goblin'
  AND nested_table_id = 'rare_goblin_loot';

-- Reduce boss gold drop
UPDATE drop_table_items
SET quantity_min = 300, quantity_max = 700
WHERE drop_table_id = 'boss_dragon'
  AND item_id = 'gold_coins';
```

## Migration Files

- **20250128140800_mmorpg_loot_tables.sql** - Schema creation
- **20250128140900_mmorpg_loot_seed_data.sql** - Example data

## Related Code

- `data/modules/economy/loot.ts` - Loot generation implementation (Task 4.6.2)
- `data/modules/economy/loot_loader.ts` - Drop table caching (optional)
- `.kiro/specs/mmorpg-nakama-godot/requirements.md` - Requirement 17
- `.kiro/specs/mmorpg-nakama-godot/design.md` - Economy Service design
