import type { AxeMatchers } from 'vitest-axe/matchers';

declare module 'vitest' {
  // The generic parameter must mirror vitest's own declaration for the augmentation to merge.
  // eslint-disable-next-line @typescript-eslint/no-empty-object-type, @typescript-eslint/no-unused-vars -- augmenting vitest's matcher interface
  interface Assertion<T = unknown> extends AxeMatchers {}
  // eslint-disable-next-line @typescript-eslint/no-empty-object-type -- augmenting vitest's matcher interface
  interface AsymmetricMatchersContaining extends AxeMatchers {}
}
