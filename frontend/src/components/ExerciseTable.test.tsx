import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router-dom';
import { describe, expect, it, vi } from 'vitest';
import { exercises } from '../test/fixtures';
import { ExerciseTable } from './ExerciseTable';

describe('ExerciseTable', () => {
  it('renders one row per exercise with labels and a link to the card', () => {
    render(
      <MemoryRouter>
        <ExerciseTable exercises={exercises} sort="name" onSort={vi.fn()} />
      </MemoryRouter>,
    );
    const rows = screen.getAllByRole('row').slice(1);
    expect(rows).toHaveLength(2);
    expect(within(rows[1]).getByRole('link', { name: 'Ankle Circles – Standing' })).toHaveAttribute(
      'href',
      '/exercises/1',
    );
    expect(within(rows[1]).getByText('Balance')).toBeInTheDocument();
    expect(within(rows[1]).getByText('Easy')).toBeInTheDocument();
  });

  it('marks the active sort column and asks for another sort', async () => {
    const onSort = vi.fn();
    render(
      <MemoryRouter>
        <ExerciseTable exercises={exercises} sort="name" onSort={onSort} />
      </MemoryRouter>,
    );
    expect(screen.getByRole('button', { name: /Name/ })).toHaveAttribute('aria-pressed', 'true');
    await userEvent.click(screen.getByRole('button', { name: /Difficulty/ }));
    expect(onSort).toHaveBeenCalledWith('difficulty');
  });
});
