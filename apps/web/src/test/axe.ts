import { configureAxe } from 'vitest-axe';

/**
 * axe for jsdom. jsdom has no canvas, so the color-contrast rule cannot run here; contrast of the
 * actual design tokens is verified by src/styles/tokens.test.ts instead.
 */
export const axe = configureAxe({ rules: { 'color-contrast': { enabled: false } } });
