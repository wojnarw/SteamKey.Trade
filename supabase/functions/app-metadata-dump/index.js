import { strToU8, gzipSync } from 'fflate';

import { serve } from '../_helpers/edge.js';
import { supabaseAdmin } from '../_helpers/supabase.js';
import { App } from '../_entities/App.js';

/**
 * Compresses apps metadata JSON with gzip and uploads it to Supabase storage
 *
 * @returns {Promise<Object>} Result of the operation
 */
const appMetadataDump = async () => {
  // Check if file age is older than 24 hours
  const { data: fileInfo, error: fileError } = await supabaseAdmin
    .storage
    .from('assets')
    .getPublicUrl('apps.metadata.json.gz');

  if (!fileError && fileInfo) {
    const response = await fetch(fileInfo.publicUrl, { method: 'HEAD' });
    if (response.ok) {
      const lastModified = new Date(response.headers.get('last-modified'));
      const now = new Date();
      const ageInHours = (now - lastModified) / (1000 * 60 * 60);

      // If file is less than 24 hours old, skip update
      if (ageInHours < 24) {
        return {
          success: true,
          message: 'App metadata is up to date (less than 24 hours old)',
          age: `${Math.round(ageInHours * 10) / 10} hours`
        };
      }
    }
  }

  // Call rpc to get_apps_metadata
  const { data, error: rpcError } = await supabaseAdmin.rpc('get_apps_metadata');

  if (rpcError) {
    throw new Error(`Failed to get apps metadata: ${rpcError.message}`);
  }

  if (!data || !Array.isArray(data)) {
    throw new Error('Invalid data returned from get_apps_metadata');
  }

  // Process data
  const processedData = data.map((app) => App.fromDB(app));

  // Convert data to JSON string
  const jsonString = JSON.stringify(processedData);

  // Compress data with gzip (best compression)
  const compressedData = gzipSync(strToU8(jsonString), { level: 9 });

  // Upload to Supabase Storage
  const { data: uploadData, error } = await supabaseAdmin
    .storage
    .from('assets')
    .upload('apps.metadata.json.gz', compressedData, {
      contentType: 'application/gzip',
      cacheControl: '86400', // 24 hours in seconds
      upsert: true // Overwrite if exists
    });

  if (error) {
    throw error;
  }

  return {
    success: true,
    message: 'App metadata successfully compressed and uploaded',
    path: uploadData.path
  };
};

serve(appMetadataDump);