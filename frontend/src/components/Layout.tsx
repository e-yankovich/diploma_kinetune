// Page layout: header with the main navigation (always visible), content, toasts.
import { NavLink, Outlet } from 'react-router-dom';
import { Toasts } from './Toasts';

const NAV_ITEMS = [
  { to: '/exercises', label: 'Exercises' },
  { to: '/families', label: 'Families' },
  { to: '/about', label: 'About' },
];

export function Layout() {
  return (
    <div className="layout">
      <header className="layout__header">
        <span className="layout__brand">Kinetune</span>
        <nav aria-label="Main navigation" className="nav">
          {NAV_ITEMS.map((item) => (
            <NavLink
              key={item.to}
              to={item.to}
              className={({ isActive }) => (isActive ? 'nav__link nav__link--active' : 'nav__link')}
            >
              {item.label}
            </NavLink>
          ))}
        </nav>
      </header>
      <main className="layout__main" id="main">
        <Outlet />
      </main>
      <Toasts />
    </div>
  );
}
