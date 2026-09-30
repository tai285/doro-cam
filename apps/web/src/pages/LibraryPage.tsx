import { usePageTitle } from '../app/use-page-title.ts';

/** Placeholder. The Memory grid arrives with the web dashboard phase (P7). */
export function LibraryPage() {
  usePageTitle('Library');
  return (
    <>
      <h1>Your library</h1>
      <p className="muted">No memories yet. Photos you capture in the app will appear here.</p>
    </>
  );
}
