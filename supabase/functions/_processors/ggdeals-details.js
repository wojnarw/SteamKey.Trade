import { App } from '../_entities/index.js';
import { saveToDatabase } from '../_helpers/updater.js';

/**
 * Processes a list of Steam app IDs by fetching game details from the GG Deals API
 * and saving the processed data to a database.
 *
 * @param {number[]} appids - An array of Steam app IDs to process.
 * @returns {Promise<Object>} A promise that resolves to an object containing the results:
 * - `errors`: An array of errors encountered during processing.
 * - `failed`: An array of records that failed to process.
 * - `successful`: An array of successfully processed records.
 */
export const processGGDealsDetails = async (appids) => {
  const records = [];
  try {
    for (let i = 0; i < appids.length; i += 100) {
      const batch = appids.slice(i, i + 100);

      const url = new URL('https://api.gg.deals/steamkeytrade/game/by-steam-app-id/');
      url.searchParams.append('ids', batch.join(',')); // max 100

      const response = await fetch(url, {
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

      for (const appid in data) {
        if (!data[appid]) {
          continue;
        }

        const { title, prices } = data[appid];

        const currentPrice = Math.min(parseFloat(prices.currentRetail), parseFloat(prices.currentKeyshops));
        const historicalPrice = Math.min(parseFloat(prices.historicalRetail), parseFloat(prices.historicalKeyshops));

        records.push({
          [App.fields.id]: parseInt(appid),
          [App.fields.title]: title,
          [App.fields.marketPrice]: currentPrice,
          [App.fields.historicalLow]: historicalPrice
        });
      }
    }

    // Save to database
    return saveToDatabase(App.table, records, App.fields.id);
  } catch (error) {
    const failed = appids.map((appid) => records.find((record) => record[App.fields.id] === appid) || { [App.fields.id]: appid });
    return { errors: [error], failed, successful: [] };
  }
};