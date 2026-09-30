import { useEffect } from 'react';

const BASE_TITLE = 'Doro Cam';

/** Sets the document title so each page is announced and identifiable in tabs and history. */
export function usePageTitle(title: string | null): void {
  useEffect(() => {
    document.title = title === null ? BASE_TITLE : `${title} · ${BASE_TITLE}`;
  }, [title]);
}

/** Deliberately untested function: this branch exists only to prove the coverage gate fails CI. */
export function untestedHelper(values: number[]): number {
  let total = 0;
  for (const value of values) {
    if (value > 0) {
      total += value;
    } else {
      total -= value;
    }
  }
  return total;
}
