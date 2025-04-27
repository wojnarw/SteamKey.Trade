import Steam from 'npm:steam-user';

import { processSteamPICS } from './steam-pics.js';

/**
 * Processes app changes from Steam PICS
 * @param {number} lastChangeNumber - Last processed change number
 * @returns {Promise<Object>} Object containing errors, failed records, and successful records. Also includes the current change number.
 */
export const processSteamPICSChanges = async (lastChangeNumber) => {
  // Create Steam client
  const client = new Steam();

  try {
    // Wait for login
    await new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        client.removeListener('loggedOn', handleLoggedOn);
        client.removeListener('error', handleError);
        reject(new Error('Steam client login timed out'));
      }, 10000);

      const handleLoggedOn = () => {
        clearTimeout(timeout);
        client.removeListener('error', handleError);
        resolve();
      };

      const handleError = (err) => {
        clearTimeout(timeout);
        client.removeListener('loggedOn', handleLoggedOn);
        reject(err);
      };

      client.once('loggedOn', handleLoggedOn);
      client.once('error', handleError);

      // Log in anonymously
      client.logOn({ anonymous: true });
    });

    // Get product changes since last change number
    const { currentChangeNumber, appChanges } = await client.getProductChanges(lastChangeNumber);

    // Filter apps that don't need a token
    const appids = appChanges
      .filter(({ needs_token }) => !needs_token)
      .map(({ appid }) => Number(appid));

    if (appids.length === 0) {
      return { errors: [], failed: [], successful: [], currentChangeNumber };
    }

    const result = await processSteamPICS(appids, client);
    return { ...result, currentChangeNumber };
  } catch (error) {
    return { errors: [error], failed: [], successful: [] };
  } finally {
    // Ensure client logs off
    client.logOff();
  }
};