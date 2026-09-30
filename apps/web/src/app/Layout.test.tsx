import { screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it } from 'vitest';
import { renderApp } from '../test/render.tsx';

describe('Layout', () => {
  it('[NFR-007] offers a skip link as the first focusable element, pointing at the main region', async () => {
    const user = userEvent.setup();
    renderApp('/');
    await screen.findByRole('heading', { level: 1 });

    await user.tab();
    const skip = screen.getByRole('link', { name: 'Skip to main content' });
    expect(skip).toHaveFocus();
    expect(skip).toHaveAttribute('href', '#main');
    expect(screen.getByRole('main')).toHaveAttribute('id', 'main');
  });

  it('has a labelled primary navigation with Library and Account', async () => {
    renderApp('/');
    const nav = await screen.findByRole('navigation', { name: 'Primary' });
    expect(nav).toContainElement(screen.getByRole('link', { name: 'Library' }));
    expect(nav).toContainElement(screen.getByRole('link', { name: 'Account' }));
  });

  it('[NFR-007] marks the current page in the navigation with aria-current', async () => {
    renderApp('/account');
    const account = await screen.findByRole('link', { name: 'Account' });
    expect(account).toHaveAttribute('aria-current', 'page');
    expect(screen.getByRole('link', { name: 'Library' })).not.toHaveAttribute('aria-current');
  });

  it('marks Library as the current page on the home page', async () => {
    renderApp('/');
    expect(await screen.findByRole('link', { name: 'Library' })).toHaveAttribute(
      'aria-current',
      'page',
    );
  });

  it('navigates with the keyboard', async () => {
    const user = userEvent.setup();
    const { router } = renderApp('/');
    await screen.findByRole('heading', { level: 1, name: 'Your library' });

    screen.getByRole('link', { name: 'Account' }).focus();
    await user.keyboard('{Enter}');

    expect(await screen.findByRole('heading', { level: 1, name: 'Account' })).toBeInTheDocument();
    expect(router.state.location.pathname).toBe('/account');
  });

  it('[NFR-007] moves focus to the main region after navigating, but not on first load', async () => {
    const user = userEvent.setup();
    renderApp('/');
    await screen.findByRole('heading', { level: 1 });
    expect(screen.getByRole('main')).not.toHaveFocus();

    await user.click(screen.getByRole('link', { name: 'Account' }));
    await screen.findByRole('heading', { level: 1, name: 'Account' });
    await waitFor(() => expect(screen.getByRole('main')).toHaveFocus());

    await user.click(screen.getByRole('link', { name: 'Library' }));
    await screen.findByRole('heading', { level: 1, name: 'Your library' });
    await waitFor(() => expect(screen.getByRole('main')).toHaveFocus());
  });
});
