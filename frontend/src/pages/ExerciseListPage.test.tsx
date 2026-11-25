// Integration: page + hooks + API client + global state, with fetch stubbed.
import { screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it, vi } from 'vitest';
import { exercises, families } from '../test/fixtures';
import { jsonResponse, mockFetch, renderAt } from '../test/utils';
import { ExerciseListPage } from './ExerciseListPage';

describe('ExerciseListPage', () => {
  it('loads the exercises and sorts by difficulty on request', async () => {
    const fetchMock = mockFetch([
      [/\/families/, () => jsonResponse(families)],
      [/\/exercises/, () => jsonResponse(exercises)],
    ]);
    renderAt('/exercises', '/exercises', <ExerciseListPage />);

    expect(screen.getByLabelText('Loading')).toBeInTheDocument();
    expect(await screen.findByText('2 exercises')).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Ankle Circles – Seated' })).toBeInTheDocument();

    await userEvent.click(screen.getByRole('button', { name: /Difficulty/ }));
    await waitFor(() =>
      expect(fetchMock).toHaveBeenCalledWith(
        '/api/v1/exercises?sort=difficulty',
        expect.anything(),
      ),
    );
  });

  it('shows an error state and a toast when the server fails', async () => {
    vi.spyOn(console, 'error').mockImplementation(() => {});
    mockFetch([
      [/\/families/, () => jsonResponse(families)],
      [
        /\/exercises/,
        () => jsonResponse({ error: { code: 'service_unavailable', message: 'down' } }, 503),
      ],
    ]);
    renderAt('/exercises', '/exercises', <ExerciseListPage />);

    expect(await screen.findByText('The exercises could not be loaded')).toBeInTheDocument();
    const message = 'The service is temporarily unavailable. Please try again in a moment.';
    expect(screen.getByRole('status')).toHaveTextContent(message);
    expect(screen.getByRole('button', { name: 'Try again' })).toBeInTheDocument();
  });

  it('shows an empty state when nothing matches', async () => {
    mockFetch([
      [/\/families/, () => jsonResponse(families)],
      [/\/exercises/, () => jsonResponse([])],
    ]);
    renderAt('/exercises', '/exercises', <ExerciseListPage />);
    expect(await screen.findByText('No exercises match the filters')).toBeInTheDocument();
  });
});
