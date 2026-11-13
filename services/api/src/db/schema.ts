// Schema index: every module owns its tables in src/modules/<module>/schema.ts and is re-exported
// here so drizzle-kit and the runtime see one schema.
export * from '../modules/auth/schema.ts';
export * from '../modules/memories/schema.ts';
export * from '../modules/presets/schema.ts';
export * from '../modules/albums/schema.ts';
