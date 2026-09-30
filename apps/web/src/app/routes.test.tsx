import { screen } from '@testing-library/react';
import { axe } from '../test/axe.ts';
import { describe, expect, it } from 'vitest';
import { renderApp } from '../test/render.tsx';

describe('routes', () => {
  const pages: ReadonlyArray<[string, string, string]> = [
    ['/', 'Your library', 'Library · Doro Cam'],
    ['/account', 'Account', 'Account · Doro Cam'],
    ['/memories/0191-abc', 'Memory', 'Memory · Doro Cam'],
    ['/does/not/exist', 'Page not found', 'Page not found · Doro Cam'],
  ];

  for (const [path, heading, title] of pages) {
    describe(path, () => {
      it(`shows the "${heading}" heading and sets the document title`, async () => {
        renderApp(path);
        expect(await screen.findByRole('heading', { level: 1, name: heading })).toBeInTheDocument();
        expect(document.title).toBe(title);
      });

      it('[NFR-007] has no detectable accessibility violations', async () => {
        const { container } = renderApp(path);
        await screen.findByRole('heading', { level: 1 });
        expect(await axe(container)).toHaveNoViolations();
      });

      it('[NFR-007] has exactly one h1 and one main landmark', async () => {
        renderApp(path);
        await screen.findByRole('heading', { level: 1 });
        expect(screen.getAllByRole('heading', { level: 1 })).toHaveLength(1);
        expect(screen.getAllByRole('main')).toHaveLength(1);
      });
    });
  }

  it('the library explains that it is empty', async () => {
    renderApp('/');
    expect(await screen.findByText(/No memories yet/)).toBeInTheDocument();
  });

  it('the memory page shows the requested ID and links back to the library', async () => {
    renderApp('/memories/0191-abc');
    expect(await screen.findByText('0191-abc')).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Back to library' })).toHaveAttribute('href', '/');
  });

  it('the not-found page links to the library', async () => {
    renderApp('/nowhere');
    expect(await screen.findByRole('link', { name: 'Go to your library' })).toHaveAttribute(
      'href',
      '/',
    );
  });
});
