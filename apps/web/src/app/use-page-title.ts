import { useEffect } from 'react';

const BASE_TITLE = 'Doro Cam';

/** Sets the document title so each page is announced and identifiable in tabs and history. */
export function usePageTitle(title: string | null): void {
  useEffect(() => {
    document.title = title === null ? BASE_TITLE : `${title} · ${BASE_TITLE}`;
  }, [title]);
}
