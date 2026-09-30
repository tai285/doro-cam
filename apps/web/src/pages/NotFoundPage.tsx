import { Link } from 'react-router';
import { usePageTitle } from '../app/use-page-title.ts';

export function NotFoundPage() {
  usePageTitle('Page not found');
  return (
    <>
      <h1>Page not found</h1>
      <p>There is nothing at this address.</p>
      <p>
        <Link to="/">Go to your library</Link>
      </p>
    </>
  );
}
