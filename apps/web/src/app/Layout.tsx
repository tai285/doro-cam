import { useEffect, useRef } from 'react';
import { NavLink, Outlet, useLocation } from 'react-router';

/**
 * Page chrome shared by every route. On navigation, focus moves to the main region so keyboard and
 * screen-reader users land on the new content instead of staying on the link they activated.
 */
export function Layout() {
  const { pathname } = useLocation();
  const main = useRef<HTMLElement>(null);
  const firstRender = useRef(true);

  useEffect(() => {
    if (firstRender.current) {
      firstRender.current = false;
      return;
    }
    main.current?.focus();
  }, [pathname]);

  return (
    <>
      <a className="skip-link" href="#main">
        Skip to main content
      </a>
      <header className="site-header">
        <p className="site-title">Doro Cam</p>
        <nav className="site-nav" aria-label="Primary">
          <NavLink to="/" end>
            Library
          </NavLink>
          <NavLink to="/account">Account</NavLink>
        </nav>
      </header>
      <main id="main" ref={main} tabIndex={-1}>
        <Outlet />
      </main>
    </>
  );
}
