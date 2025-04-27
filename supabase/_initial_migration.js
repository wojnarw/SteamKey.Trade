#!/usr/bin/env node
/* eslint-disable no-console */

import { readFileSync, existsSync, mkdirSync, writeFileSync, unlinkSync, statSync, readdirSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

// Get the equivalent of __dirname in ES modules
const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// Simple function to parse schema_paths from config.toml
function parseSchemaPathsFromToml(content) {
  // Look for the db.migrations section and schema_paths array
  const schemaPathsMatch = content.match(/\[db\.migrations\]([\s\S]*?)schema_paths\s*=\s*\[([\s\S]*?)\]/);

  if (!schemaPathsMatch || !schemaPathsMatch[2]) {
    return [];
  }

  // Extract the array content
  const arrayContent = schemaPathsMatch[2];

  // Split by commas and process each entry
  return arrayContent.split(',')
    .map(line => {
      // Extract content between quotes
      const match = line.match(/["'](.+?)["']/);
      return match ? match[1].trim() : null;
    })
    .filter(Boolean); // Remove any null/empty values
}

// Read the config.toml file
const configPath = join(__dirname, 'config.toml');
let configContent;

try {
  configContent = readFileSync(configPath, 'utf8');
} catch (error) {
  console.error(`Error reading config file: ${error.message}`);
  process.exit(1);
}

// Parse the schema_paths from the TOML content
const schemaPaths = parseSchemaPathsFromToml(configContent);

if (!schemaPaths.length) {
  console.error('No schema paths found in config.toml');
  process.exit(1);
}

console.log(`Found ${schemaPaths.length} schema files to process`);

// Create output directory if it doesn't exist
const migrationsDir = join(__dirname, 'migrations');
if (!existsSync(migrationsDir)) {
  mkdirSync(migrationsDir, { recursive: true });
}

// Create a timestamp in yyyymmddhhmmss format
const now = new Date();
const timestamp = now.getFullYear().toString() +
                 (now.getMonth() + 1).toString().padStart(2, '0') +
                 now.getDate().toString().padStart(2, '0') +
                 now.getHours().toString().padStart(2, '0') +
                 now.getMinutes().toString().padStart(2, '0') +
                 now.getSeconds().toString().padStart(2, '0');

const outputFile = join(migrationsDir, `${timestamp}_initial_schemas.sql`);
let combinedSchema = `-- Initial schema migration created on ${new Date().toISOString()}\nset check_function_bodies=off;\n\n`;

// Process each schema file
schemaPaths.forEach((schemaPath) => {
  // Convert relative path to absolute path
  const absolutePath = join(__dirname, schemaPath);

  try {
    // Read the schema file
    const schemaContent = readFileSync(absolutePath, 'utf8');

    // Add file header comment
    combinedSchema += '-- ============================================================================\n';
    combinedSchema += `-- Schema file: ${schemaPath}\n`;
    combinedSchema += '-- ============================================================================\n\n';
    combinedSchema += schemaContent;

    // Add newlines between files
    if (!combinedSchema.endsWith('\n\n')) {
      combinedSchema += '\n\n';
    }

    console.log(`Processed: ${schemaPath}`);
  } catch (error) {
    console.error(`Error processing ${schemaPath}: ${error.message}`);
  }
});

// Remove any existing files in migrationsDir
const files = readdirSync(migrationsDir);
files.forEach((file) => {
  const filePath = join(migrationsDir, file);
  try {
    const stats = statSync(filePath);
    if (stats.isFile() && file !== outputFile) {
      unlinkSync(filePath);
      console.log(`Removed existing file: ${file}`);
    }
  } catch (error) {
    console.error(`Error removing file ${file}: ${error.message}`);
  }
});

// Write the combined schema to the output file
try {
  writeFileSync(outputFile, combinedSchema);
  console.log(`Successfully created migration file: ${outputFile}`);
} catch (error) {
  console.error(`Error writing migration file: ${error.message}`);
  process.exit(1);
}