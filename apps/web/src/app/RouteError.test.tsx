import { screen } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { axe } from '../test/axe.ts';
import { renderApp } from '../test/render.tsx';
import { Layout } from './Layout.tsx';
import { RouteError } from './RouteError.tsx';

function Boom(): never {
  throw new Error('secret internal detail: db password is hunter2');
}

describe('RouteError', () => {
  beforeEach(() => {
    // React logs errors thrown during render; keep the test output readable.
    vi.spyOn(console, 'error').mockImplementation(() => undefined);
  });
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('[NFR-008] shows a generic message and never the error internals', async () => {
    renderApp('/', [
      {
        path: '/',
        element: <Layout />,
        errorElement: <RouteError />,
        children: [{ index: true, element: <Boom /> }],
      },
    ]);
    expect(
      await screen.findByRole('heading', { level: 1, name: 'Something went wrong' }),
    ).toBeInTheDocument();
    expect(screen.getByText('Please try again in a moment.')).toBeInTheDocument();
    expect(document.body).not.toHaveTextContent('hunter2');
    expect(document.body).not.toHaveTextContent('secret internal detail');
    expect(document.title).toBe('Something went wrong · Doro Cam');
    expect(screen.getByRole('link', { name: 'Go to your library' })).toHaveAttribute('href', '/');
  });

  it('shows "Page not found" for a 404 response thrown by a route', async () => {
    renderApp('/', [
      {
        path: '/',
        element: <Layout />,
        errorElement: <RouteError />,
        children: [
          {
            index: true,
            loader: () => {
              // eslint-disable-next-line @typescript-eslint/only-throw-error -- React Router's documented pattern
              throw new Response('missing', { status: 404 });
            },
            element: <p>never rendered</p>,
          },
        ],
      },
    ]);
    expect(
      await screen.findByRole('heading', { level: 1, name: 'Page not found' }),
    ).toBeInTheDocument();
    expect(screen.getByText('There is nothing at this address.')).toBeInTheDocument();
  });

  it('treats a non-404 response as a generic failure', async () => {
    renderApp('/', [
      {
        path: '/',
        element: <Layout />,
        errorElement: <RouteError />,
        children: [
          {
            index: true,
            loader: () => {
              // eslint-disable-next-line @typescript-eslint/only-throw-error -- React Router's documented pattern
              throw new Response('broken', { status: 500 });
            },
            element: <p>never rendered</p>,
          },
        ],
      },
    ]);
    expect(
      await screen.findByRole('heading', { level: 1, name: 'Something went wrong' }),
    ).toBeInTheDocument();
  });

  it('[NFR-007] has no detectable accessibility violations', async () => {
    const { container } = renderApp('/', [
      {
        path: '/',
        element: <Layout />,
        errorElement: <RouteError />,
        children: [{ index: true, element: <Boom /> }],
      },
    ]);
    await screen.findByRole('heading', { level: 1 });
    expect(await axe(container)).toHaveNoViolations();
  });
});
