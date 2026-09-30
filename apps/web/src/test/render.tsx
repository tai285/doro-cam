import { render } from '@testing-library/react';
import { createMemoryRouter, type RouteObject } from 'react-router';
import { RouterProvider } from 'react-router/dom';
import { routes } from '../app/routes.tsx';

/** Renders the real route table at [path] using an in-memory router. */
export function renderApp(path = '/', routeTable: RouteObject[] = routes) {
  const router = createMemoryRouter(routeTable, { initialEntries: [path] });
  const utils = render(<RouterProvider router={router} />);
  return { router, ...utils };
}
