import { screen } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';
import { detail } from '../test/fixtures';
import { jsonResponse, mockFetch, renderAt } from '../test/utils';
import { ExerciseDetailPage } from './ExerciseDetailPage';

describe('ExerciseDetailPage', () => {
  it('shows the joints, the variations with their level and the regressions', async () => {
    mockFetch([[/\/exercises\/1$/, () => jsonResponse(detail)]]);
    renderAt('/exercises/1', '/exercises/:id', <ExerciseDetailPage />);

    expect(
      await screen.findByRole('heading', { name: 'Ankle Circles – Standing' }),
    ).toBeInTheDocument();
    expect(screen.getByText('Medium')).toBeInTheDocument();
    expect(screen.getByText('Easier')).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: /Regressions \(easier\)/ })).toHaveTextContent(
      '(1)',
    );
    expect(screen.getByText('No compensation needed.')).toBeInTheDocument();
  });

  it('shows "not found" for an unknown exercise (404)', async () => {
    vi.spyOn(console, 'error').mockImplementation(() => {});
    mockFetch([
      [
        /\/exercises\/9999$/,
        () => jsonResponse({ error: { code: 'not_found', message: 'x' } }, 404),
      ],
    ]);
    renderAt('/exercises/9999', '/exercises/:id', <ExerciseDetailPage />);
    expect(await screen.findByText('Exercise not found')).toBeInTheDocument();
    expect(screen.queryByRole('status')).not.toBeInTheDocument();
  });

  it('does not call the API for an invalid id', async () => {
    const fetchMock = mockFetch([]);
    vi.spyOn(console, 'error').mockImplementation(() => {});
    renderAt('/exercises/abc', '/exercises/:id', <ExerciseDetailPage />);
    expect(await screen.findByText('Exercise not found')).toBeInTheDocument();
    expect(fetchMock).not.toHaveBeenCalledWith('/api/v1/exercises/abc', expect.anything());
  });
});
