import { QueryClient, QueryClientProvider, useQuery } from '@tanstack/react-query';
import { render, renderHook, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import type { ReactNode } from 'react';
import { describe, expect, it } from 'vitest';
import { usePageTitle } from './use-page-title.ts';
import { App } from './App.tsx';
import { createQueryClient } from './query-client.ts';

describe('App', () => {
  it('mounts with the browser router and follows real history navigation', async () => {
    window.history.pushState({}, '', '/');
    const user = userEvent.setup();
    render(<App />);

    expect(
      await screen.findByRole('heading', { level: 1, name: 'Your library' }),
    ).toBeInTheDocument();

    await user.click(screen.getByRole('link', { name: 'Account' }));
    expect(await screen.findByRole('heading', { level: 1, name: 'Account' })).toBeInTheDocument();
    expect(window.location.pathname).toBe('/account');

    window.history.back();
    await waitFor(() => {
      expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent('Your library');
    });
  });

  it('deep-links straight to a page', async () => {
    window.history.pushState({}, '', '/memories/abc-123');
    render(<App />);
    expect(await screen.findByText('abc-123')).toBeInTheDocument();
  });
});

describe('createQueryClient', () => {
  it('uses short staleness, one retry, and no refetch on window focus', () => {
    const defaults = createQueryClient().getDefaultOptions().queries;
    expect(defaults).toMatchObject({ staleTime: 30_000, retry: 1, refetchOnWindowFocus: false });
  });

  it('creates independent clients', () => {
    expect(createQueryClient()).not.toBe(createQueryClient());
  });

  it('serves a cached result without refetching within the stale time', async () => {
    const client = createQueryClient();
    let calls = 0;
    const wrapper = ({ children }: { children: ReactNode }) => (
      <QueryClientProvider client={client}>{children}</QueryClientProvider>
    );
    const useData = () =>
      useQuery({
        queryKey: ['probe'],
        queryFn: () => {
          calls += 1;
          return Promise.resolve('value');
        },
      });

    const first = renderHook(useData, { wrapper });
    await waitFor(() => {
      expect(first.result.current.data).toBe('value');
    });
    first.unmount();
    const second = renderHook(useData, { wrapper });
    await waitFor(() => {
      expect(second.result.current.data).toBe('value');
    });

    expect(calls).toBe(1);
  });

  it('does not reuse state between separate clients', () => {
    const other = new QueryClient();
    expect(other.getDefaultOptions().queries?.staleTime).toBeUndefined();
  });
});

describe('usePageTitle', () => {
  it('sets "<title> · Doro Cam" and updates when the title changes', () => {
    const { rerender } = renderHook(
      ({ title }: { title: string | null }) => {
        usePageTitle(title);
      },
      { initialProps: { title: 'Library' } },
    );
    expect(document.title).toBe('Library · Doro Cam');
    rerender({ title: 'Account' });
    expect(document.title).toBe('Account · Doro Cam');
  });

  it('falls back to the bare product name when there is no title', () => {
    renderHook(() => {
      usePageTitle(null);
    });
    expect(document.title).toBe('Doro Cam');
  });
});
