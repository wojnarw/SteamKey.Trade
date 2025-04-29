import { App } from '../_entities/index.js';
import { saveToDatabase } from '../_helpers/updater.js';

/**
 * Processes a recently changed deals from the GG Deals API and saves the processed data to a database.
 *
 * @param {string} lastCheck - The timestamp of the last check to filter deals.
 * @returns {Promise<Object>} A promise that resolves to an object containing the results:
 * - `errors`: An array of errors encountered during processing.
 * - `failed`: An array of records that failed to process.
 * - `successful`: An array of successfully processed records.
 */
export const processGGDealsPrices = async (lastCheck) => {
  try {
    let allGames = {};
    const initialUrl = new URL('https://api.gg.deals/steamkeytrade/game/recently-changed-deals/');

    if (lastCheck) {
      initialUrl.searchParams.append('since', Math.floor(new Date(lastCheck).getTime() / 1000).toString());
    }

    // Process all pages until next is null
    let currentUrl = initialUrl.toString();

    do {
      const response = await fetch(currentUrl, {
        headers: {
          'X-API-Key': Deno.env.get('GGDEALS_API_KEY')
        }
      });

      if (!response.ok) {
        throw new Error(`GG Deals API returned ${response.status}: ${response.statusText}`);
      }

      const { data, success } = await response.json();

      if (!data || !success) {
        throw new Error(`GG Deals API returned an error: ${JSON.stringify(data)}`);
      }

      const { next, games } = data;
      if (games) {
        allGames = { ...games, ...allGames };
      }

      // Set next URL for the next iteration
      currentUrl = next;
    } while (currentUrl);

    if (Object.keys(allGames).length === 0) {
      return { errors: [], failed: [], successful: [] };
    }

    const records = [];
    for (const { steamIds, prices } of Object.values(allGames)) {
      for (const appid of steamIds) {
        const currentPrice = Math.min(parseFloat(prices.currentRetail), parseFloat(prices.currentKeyshops));
        const historicalPrice = Math.min(parseFloat(prices.historicalRetail), parseFloat(prices.historicalKeyshops));

        records.push({
          [App.fields.id]: parseInt(appid),
          [App.fields.marketPrice]: currentPrice,
          [App.fields.historicalLow]: historicalPrice
        });
      }
    }

    // Save to database
    return saveToDatabase(App.table, records, App.fields.id);
  } catch (error) {
    return { errors: [error], failed: [], successful: [] };
  }
};