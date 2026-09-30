import { Link, isRouteErrorResponse, useRouteError } from 'react-router';
import { usePageTitle } from './use-page-title.ts';

/** Shown when a route throws while loading or rendering. It never displays error internals. */
export function RouteError() {
  const error = useRouteError();
  usePageTitle('Something went wrong');
  const notFound = isRouteErrorResponse(error) && error.status === 404;
  return (
    <main id="main" tabIndex={-1}>
      <h1>{notFound ? 'Page not found' : 'Something went wrong'}</h1>
      <p>{notFound ? 'There is nothing at this address.' : 'Please try again in a moment.'}</p>
      <p>
        <Link to="/">Go to your library</Link>
      </p>
    </main>
  );
}
