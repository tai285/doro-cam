import { useEffect, useRef } from 'react';
import { NavLink, Outlet, useLocation } from 'react-router';
import { useMe } from '../auth/RequireAuth.tsx';

/**
 * Page chrome shared by every route. On navigation, focus moves to the main region so keyboard and
 * screen-reader users land on the new content instead of staying on the link they activated.
 */
export function Layout() {
  const { pathname } = useLocation();
  const main = useRef<HTMLElement>(null);
  const firstRender = useRef(true);
  const me = useMe();
  const signedIn = me.data !== undefined && me.data !== null;

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
          {signedIn ? (
            <>
              <NavLink to="/" end>
                Library
              </NavLink>
              <NavLink to="/albums">Albums</NavLink>
              <NavLink to="/insights">Insights</NavLink>
              <NavLink to="/presets">Presets</NavLink>
              <NavLink to="/account">Account</NavLink>
            </>
          ) : (
            <>
              <NavLink to="/sign-in">Sign in</NavLink>
              <NavLink to="/sign-up">Create account</NavLink>
            </>
          )}
        </nav>
      </header>
      <main id="main" ref={main} tabIndex={-1}>
        <Outlet />
      </main>
    </>
  );
}
