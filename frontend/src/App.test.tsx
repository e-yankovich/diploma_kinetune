// Routing: the layout with navigation is on every route; unknown URLs show the 404 page.
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router-dom';
import { describe, expect, it } from 'vitest';
import { App } from './App';
import { AppStateProvider } from './state/AppStateProvider';
import { families } from './test/fixtures';
import { jsonResponse, mockFetch } from './test/utils';

function renderApp(path: string) {
  return render(
    <AppStateProvider>
      <MemoryRouter initialEntries={[path]}>
        <App />
      </MemoryRouter>
    </AppStateProvider>,
  );
}

describe('App routes', () => {
  it('shows the about page with the main navigation', () => {
    renderApp('/about');
    expect(screen.getByRole('heading', { name: 'About Kinetune' })).toBeInTheDocument();
    expect(screen.getByRole('navigation', { name: 'Main navigation' })).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'About' })).toHaveClass('nav__link--active');
  });

  it('shows the 404 page for an unknown URL', () => {
    renderApp('/no-such-page');
    expect(screen.getByRole('heading', { name: 'Page not found' })).toBeInTheDocument();
  });

  it('navigates between pages with the main navigation', async () => {
    mockFetch([[/\/families/, () => jsonResponse(families)]]);
    renderApp('/about');
    await userEvent.click(screen.getByRole('link', { name: 'Families' }));
    expect(await screen.findByRole('heading', { name: 'Exercise families' })).toBeInTheDocument();
  });
});
