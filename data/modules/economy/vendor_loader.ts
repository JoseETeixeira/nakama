/**
 * Economy Module: Vendor Catalog Loader
 *
 * Loads vendor configuration data from JSON files into runtime memory.
 * Provides interface for accessing vendor catalogs, prices, and stock limits.
 *
 * Phase 4, Task: 4.5.1 - Create vendor configuration data
 * Requirements: 16 (Vendor Systems)
 * Design: Economy Service (vendor catalog schema)
 *
 * Features:
 * - Load vendor catalogs from JSON files at startup
 * - In-memory catalog storage for fast RPC access
 * - Stock tracking with reset intervals
 * - Price lookup and validation
 * - Multi-currency support
 *
 * File Structure:
 * - data/vendor_catalogs/*.json - Vendor configuration files
 * - Each file defines: vendor_id, name, type, location, catalog items
 * - Catalog items include: item_id, name, price, stock_limit, sellable flag
 */

interface VendorCatalogItem {
  item_id: string;
  name: string;
  description: string;
  price: number;
  currency: string;
  stock_limit: number | null;
  stock_reset_interval: number | null; // seconds
  sellable: boolean;
  sell_price: number;
  metadata: Record<string, any>;
}

interface VendorCatalog {
  vendor_id: string;
  vendor_name: string;
  vendor_type: string;
  location: string;
  description: string;
  catalog: VendorCatalogItem[];
}

interface VendorStock {
  vendor_id: string;
  item_id: string;
  current_stock: number;
  last_reset: number; // timestamp
}

/**
 * Global vendor catalog storage
 * Loaded at runtime initialization
 */
const vendorCatalogs: Map<string, VendorCatalog> = new Map();
const vendorStock: Map<string, VendorStock> = new Map(); // key: "vendor_id:item_id"

/**
 * Load all vendor catalogs from JSON files
 *
 * Called during runtime initialization (InitModule).
 * Reads all JSON files from data/vendor_catalogs/ directory.
 * Populates vendorCatalogs map for RPC access.
 *
 * @param nk Nakama runtime API
 * @param logger Nakama logger instance
 */
export function loadVendorCatalogs(nk: any, logger: any): void {
  logger.info('[vendor_loader] Loading vendor catalogs...');

  // List of vendor catalog files to load
  // In production, this could read from a directory or database
  const catalogFiles = [
    'starter_vendor.json',
    'blacksmith.json',
    'alchemist.json'
  ];

  let loadedCount = 0;

  for (const filename of catalogFiles) {
    try {
      // Read JSON file from data/vendor_catalogs/
      const filePath = `data/vendor_catalogs/${filename}`;
      const fileContent = nk.readFile(filePath);
      const catalog: VendorCatalog = JSON.parse(fileContent);

      // Store in memory
      vendorCatalogs.set(catalog.vendor_id, catalog);

      // Initialize stock for items with stock limits
      for (const item of catalog.catalog) {
        if (item.stock_limit !== null) {
          const stockKey = `${catalog.vendor_id}:${item.item_id}`;
          vendorStock.set(stockKey, {
            vendor_id: catalog.vendor_id,
            item_id: item.item_id,
            current_stock: item.stock_limit,
            last_reset: Date.now()
          });
        }
      }

      loadedCount++;
      logger.info('[vendor_loader] Loaded catalog: %s (%d items)',
        catalog.vendor_id, catalog.catalog.length
      );
    } catch (error) {
      logger.error('[vendor_loader] Failed to load %s: %s', filename, error);
    }
  }

  logger.info('[vendor_loader] Loaded %d vendor catalogs', loadedCount);
}

/**
 * Get vendor catalog by vendor_id
 *
 * @param vendor_id Unique vendor identifier
 * @returns VendorCatalog or null if not found
 */
export function getVendorCatalog(vendor_id: string): VendorCatalog | null {
  return vendorCatalogs.get(vendor_id) || null;
}

/**
 * Get all vendor catalogs
 *
 * @returns Array of all loaded vendor catalogs
 */
export function getAllVendorCatalogs(): VendorCatalog[] {
  return Array.from(vendorCatalogs.values());
}

/**
 * Get catalog item by vendor_id and item_id
 *
 * @param vendor_id Unique vendor identifier
 * @param item_id Item identifier within the catalog
 * @returns VendorCatalogItem or null if not found
 */
export function getCatalogItem(vendor_id: string, item_id: string): VendorCatalogItem | null {
  const catalog = vendorCatalogs.get(vendor_id);
  if (!catalog) {
    return null;
  }

  return catalog.catalog.find(item => item.item_id === item_id) || null;
}

/**
 * Get current stock for an item
 *
 * @param vendor_id Vendor identifier
 * @param item_id Item identifier
 * @returns Current stock count, or null if unlimited stock
 */
export function getCurrentStock(vendor_id: string, item_id: string): number | null {
  const stockKey = `${vendor_id}:${item_id}`;
  const stock = vendorStock.get(stockKey);

  if (!stock) {
    // Item has unlimited stock
    return null;
  }

  // Check if stock needs to reset
  const item = getCatalogItem(vendor_id, item_id);
  if (item && item.stock_reset_interval !== null) {
    const now = Date.now();
    const timeSinceReset = (now - stock.last_reset) / 1000; // convert to seconds

    if (timeSinceReset >= item.stock_reset_interval) {
      // Reset stock
      stock.current_stock = item.stock_limit!;
      stock.last_reset = now;
      vendorStock.set(stockKey, stock);
    }
  }

  return stock.current_stock;
}

/**
 * Decrease stock for an item (called when player purchases)
 *
 * @param vendor_id Vendor identifier
 * @param item_id Item identifier
 * @param quantity Quantity to decrease
 * @returns true if successful, false if insufficient stock
 */
export function decreaseStock(vendor_id: string, item_id: string, quantity: number): boolean {
  const stockKey = `${vendor_id}:${item_id}`;
  const stock = vendorStock.get(stockKey);

  if (!stock) {
    // Unlimited stock - always succeeds
    return true;
  }

  if (stock.current_stock < quantity) {
    // Insufficient stock
    return false;
  }

  stock.current_stock -= quantity;
  vendorStock.set(stockKey, stock);
  return true;
}

/**
 * Increase stock for an item (called when player sells)
 *
 * Note: Stock increases are optional depending on game design.
 * Some games don't increase vendor stock when players sell items.
 *
 * @param vendor_id Vendor identifier
 * @param item_id Item identifier
 * @param quantity Quantity to increase
 */
export function increaseStock(vendor_id: string, item_id: string, quantity: number): void {
  const stockKey = `${vendor_id}:${item_id}`;
  const stock = vendorStock.get(stockKey);

  if (!stock) {
    // Unlimited stock - no need to track
    return;
  }

  const item = getCatalogItem(vendor_id, item_id);
  if (!item || item.stock_limit === null) {
    return;
  }

  // Increase stock, but cap at stock_limit
  stock.current_stock = Math.min(stock.current_stock + quantity, item.stock_limit);
  vendorStock.set(stockKey, stock);
}

/**
 * RPC: Get Vendor Catalog
 *
 * Returns the catalog for a specific vendor, including current stock levels.
 *
 * @param ctx Nakama context
 * @param logger Nakama logger
 * @param nk Nakama runtime API
 * @param payload JSON string: {vendor_id: string}
 * @returns JSON string: {catalog: VendorCatalog, stock: Record<string, number>}
 */
export function rpcGetVendorCatalog(
  ctx: any,
  logger: any,
  nk: any,
  payload: string
): string {
  logger.info('[get_vendor_catalog] RPC invoked by account: %s', ctx.userId);

  let request: { vendor_id: string };
  try {
    request = JSON.parse(payload);
  } catch (error) {
    logger.error('[get_vendor_catalog] Invalid JSON payload: %s', error);
    throw new Error('Invalid request payload');
  }

  const { vendor_id } = request;

  if (!vendor_id) {
    throw new Error('vendor_id is required');
  }

  const catalog = getVendorCatalog(vendor_id);

  if (!catalog) {
    throw new Error(`Vendor not found: ${vendor_id}`);
  }

  // Build stock information
  const stockInfo: Record<string, number | null> = {};
  for (const item of catalog.catalog) {
    stockInfo[item.item_id] = getCurrentStock(vendor_id, item.item_id);
  }

  const response = {
    catalog: catalog,
    stock: stockInfo
  };

  return JSON.stringify(response);
}
