/*
 * MMORPG Loot System - Seed Data
 *
 * Populates drop_tables and drop_table_items with example loot configurations.
 * This demonstrates the relational loot system with various entity types,
 * drop chances, nested tables, and guaranteed drops.
 *
 * Examples:
 * - goblin_common: Basic enemy drops
 * - elite_goblin: Enhanced drops with nested rare table
 * - boss_dragon: Boss encounter with guaranteed + RNG drops
 * - resource_iron_ore: Resource gathering node
 */

-- +migrate Up

-- Basic goblin enemy drop table
INSERT INTO drop_tables (drop_table_id, description, entity_type, drop_policy) VALUES
('goblin_common', 'Common loot from basic goblin enemies', 'npc', 'per_killer');

INSERT INTO drop_table_items (drop_table_id, item_id, drop_chance, quantity_min, quantity_max, metadata) VALUES
('goblin_common', 'gold_coins', 1.0, 5, 15, '{"item_type": "currency", "rarity": "common"}'),
('goblin_common', 'goblin_ear', 0.3, 1, 1, '{"item_type": "quest_item", "rarity": "common", "description": "A smelly goblin ear, useful for certain quests"}'),
('goblin_common', 'potion_health_minor', 0.15, 1, 2, '{"item_type": "consumable", "rarity": "common"}'),
('goblin_common', 'rusty_dagger', 0.05, 1, 1, '{"item_type": "weapon", "rarity": "common", "description": "A worn dagger with minimal combat value"}');

-- Rare goblin loot nested table
INSERT INTO drop_tables (drop_table_id, description, entity_type, drop_policy) VALUES
('rare_goblin_loot', 'Rare loot table for nested drops from elite enemies', 'npc', 'per_killer');

INSERT INTO drop_table_items (drop_table_id, item_id, drop_chance, quantity_min, quantity_max, metadata) VALUES
('rare_goblin_loot', 'goblin_king_token', 0.5, 1, 1, '{"item_type": "quest_item", "rarity": "rare", "description": "A ceremonial token of the goblin king''s guard"}'),
('rare_goblin_loot', 'enchanted_ring_agility', 0.3, 1, 1, '{"item_type": "equipment", "rarity": "rare", "description": "A magical ring that enhances agility", "stats": {"agility": 5}}'),
('rare_goblin_loot', 'gems', 0.2, 1, 5, '{"item_type": "currency", "rarity": "rare"}');

-- Elite goblin with nested rare table
INSERT INTO drop_tables (drop_table_id, description, entity_type, drop_policy) VALUES
('elite_goblin', 'Enhanced loot from elite goblin warriors with rare drop table support', 'npc', 'per_killer');

INSERT INTO drop_table_items (drop_table_id, item_id, drop_chance, quantity_min, quantity_max, metadata) VALUES
('elite_goblin', 'gold_coins', 1.0, 25, 50, '{"item_type": "currency", "rarity": "common"}'),
('elite_goblin', 'goblin_ear', 0.5, 1, 2, '{"item_type": "quest_item", "rarity": "common"}'),
('elite_goblin', 'potion_health_greater', 0.25, 1, 3, '{"item_type": "consumable", "rarity": "uncommon"}'),
('elite_goblin', 'steel_shortsword', 0.1, 1, 1, '{"item_type": "weapon", "rarity": "uncommon", "description": "A well-crafted shortsword"}');

-- Nested table reference (2% chance to roll rare_goblin_loot)
INSERT INTO drop_table_items (drop_table_id, nested_table_id, drop_chance, quantity_min, quantity_max, metadata) VALUES
('elite_goblin', 'rare_goblin_loot', 0.02, 1, 1, '{"description": "Very rare drops from elite goblins"}');

-- Dragon legendary loot nested table
INSERT INTO drop_tables (drop_table_id, description, entity_type, drop_policy) VALUES
('dragon_legendary_loot', 'Legendary loot from dragon bosses - nested rare table', 'boss', 'shared_party');

INSERT INTO drop_table_items (drop_table_id, item_id, drop_chance, quantity_min, quantity_max, metadata) VALUES
('dragon_legendary_loot', 'dragonbane_sword', 0.4, 1, 1, '{"item_type": "weapon", "rarity": "legendary", "description": "A legendary sword forged to slay dragons", "stats": {"attack": 150, "dragon_damage_bonus": 50}}'),
('dragon_legendary_loot', 'dragonheart_amulet', 0.35, 1, 1, '{"item_type": "equipment", "rarity": "legendary", "description": "An amulet containing the essence of a dragon''s heart", "stats": {"max_hp": 500, "fire_resistance": 75}}'),
('dragon_legendary_loot', 'dragon_egg', 0.25, 1, 1, '{"item_type": "pet_item", "rarity": "legendary", "description": "A dragon egg that can be hatched into a companion"}');

-- Boss dragon with guaranteed + RNG drops
INSERT INTO drop_tables (drop_table_id, description, entity_type, drop_policy) VALUES
('boss_dragon', 'Epic loot from dragon boss encounters with guaranteed + random drops', 'boss', 'shared_party');

-- Guaranteed drops (is_guaranteed = TRUE)
INSERT INTO drop_table_items (drop_table_id, item_id, drop_chance, quantity_min, quantity_max, is_guaranteed, metadata) VALUES
('boss_dragon', 'dragon_scale', 1.0, 3, 5, TRUE, '{"item_type": "crafting_material", "rarity": "epic", "description": "A pristine dragon scale, essential for crafting legendary armor"}'),
('boss_dragon', 'gold_coins', 1.0, 500, 1000, TRUE, '{"item_type": "currency", "rarity": "common"}');

-- RNG-based drops
INSERT INTO drop_table_items (drop_table_id, item_id, drop_chance, quantity_min, quantity_max, metadata) VALUES
('boss_dragon', 'dragon_fang', 0.5, 1, 2, '{"item_type": "crafting_material", "rarity": "epic"}'),
('boss_dragon', 'legendary_weapon_fragment', 0.15, 1, 1, '{"item_type": "crafting_material", "rarity": "legendary", "description": "A fragment of a legendary weapon, collect 5 to craft"}'),
('boss_dragon', 'potion_resurrection', 0.3, 1, 3, '{"item_type": "consumable", "rarity": "epic", "description": "Revives a fallen party member"}');

-- Nested legendary table (5% chance)
INSERT INTO drop_table_items (drop_table_id, nested_table_id, drop_chance, quantity_min, quantity_max, metadata) VALUES
('boss_dragon', 'dragon_legendary_loot', 0.05, 1, 1, '{"description": "Extremely rare legendary drops from dragons"}');

-- Resource node: Iron ore
INSERT INTO drop_tables (drop_table_id, description, entity_type, drop_policy) VALUES
('resource_iron_ore', 'Loot from mining iron ore resource nodes', 'resource_node', 'per_gatherer');

INSERT INTO drop_table_items (drop_table_id, item_id, drop_chance, quantity_min, quantity_max, metadata) VALUES
('resource_iron_ore', 'iron_ore', 1.0, 1, 3, '{"item_type": "crafting_material", "rarity": "common", "description": "Raw iron ore for smelting"}'),
('resource_iron_ore', 'rough_stone', 0.4, 1, 2, '{"item_type": "crafting_material", "rarity": "common", "description": "Common stone fragments"}'),
('resource_iron_ore', 'iron_ore_rich', 0.1, 1, 1, '{"item_type": "crafting_material", "rarity": "uncommon", "description": "High-quality iron ore with better yield"}'),
('resource_iron_ore', 'uncut_gem', 0.02, 1, 1, '{"item_type": "crafting_material", "rarity": "rare", "description": "A raw gemstone found while mining"}');

-- +migrate Down

-- Clean up seed data
DELETE FROM drop_table_items WHERE drop_table_id IN (
  'goblin_common', 'elite_goblin', 'rare_goblin_loot',
  'boss_dragon', 'dragon_legendary_loot', 'resource_iron_ore'
);

DELETE FROM drop_tables WHERE drop_table_id IN (
  'goblin_common', 'elite_goblin', 'rare_goblin_loot',
  'boss_dragon', 'dragon_legendary_loot', 'resource_iron_ore'
);
