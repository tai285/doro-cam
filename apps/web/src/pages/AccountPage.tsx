import { usePageTitle } from '../app/use-page-title.ts';

/** Placeholder. Sessions, storage usage and account deletion arrive with P4 and P7. */
export function AccountPage() {
  usePageTitle('Account');
  return (
    <>
      <h1>Account</h1>
      <p className="muted">Sign-in and account settings will appear here.</p>
    </>
  );
}
