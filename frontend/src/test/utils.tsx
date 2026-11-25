// Test helpers: render with router + global state; fake fetch responses.
import { render } from '@testing-library/react';
import type { ReactElement } from 'react';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import { vi } from 'vitest';
import { Layout } from '../components/Layout';
import { AppStateProvider } from '../state/AppStateProvider';

export function renderAt(path: string, routePath: string, element: ReactElement) {
  return render(
    <AppStateProvider>
      <MemoryRouter initialEntries={[path]}>
        <Routes>
          <Route element={<Layout />}>
            <Route path={routePath} element={element} />
            <Route path="*" element={<p>other page</p>} />
          </Route>
        </Routes>
      </MemoryRouter>
    </AppStateProvider>,
  );
}

export function jsonResponse(body: unknown, status = 200, headers: Record<string, string> = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', ...headers },
  });
}

/** Stubs fetch: each URL pattern returns a response; unknown URLs fail the test. */
export function mockFetch(routes: [RegExp, () => Response][]) {
  const fetchMock = vi.fn(async (input: RequestInfo | URL) => {
    const url = String(input);
    const match = routes.find(([pattern]) => pattern.test(url));
    if (!match) throw new Error(`Unexpected request: ${url}`);
    return match[1]();
  });
  vi.stubGlobal('fetch', fetchMock);
  return fetchMock;
}
