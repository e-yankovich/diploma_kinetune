import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it, vi } from 'vitest';
import { DEFAULT_FILTERS } from '../state/appState';
import { families } from '../test/fixtures';
import { ExerciseFiltersForm } from './ExerciseFilters';

function setup() {
  const onApply = vi.fn();
  const onReset = vi.fn();
  render(
    <ExerciseFiltersForm
      value={DEFAULT_FILTERS}
      families={families}
      onApply={onApply}
      onReset={onReset}
    />,
  );
  return { onApply, onReset, user: userEvent.setup() };
}

describe('ExerciseFiltersForm', () => {
  it('shows a validation error and does not apply a too short search', async () => {
    const { onApply, user } = setup();
    await user.type(screen.getByLabelText('Search by name'), 'a');
    await user.click(screen.getByRole('button', { name: 'Apply' }));
    expect(screen.getByText('Enter at least 2 characters.')).toBeInTheDocument();
    expect(screen.getByLabelText('Search by name')).toHaveAttribute('aria-invalid', 'true');
    expect(onApply).not.toHaveBeenCalled();
  });

  it('applies the selected filters', async () => {
    const { onApply, user } = setup();
    await user.type(screen.getByLabelText('Search by name'), 'ankle');
    await user.selectOptions(screen.getByLabelText('Mode'), 'static');
    await user.selectOptions(screen.getByLabelText('Difficulty'), '2');
    await user.selectOptions(screen.getByLabelText('Family'), '1');
    await user.click(screen.getByRole('button', { name: 'Apply' }));
    expect(onApply).toHaveBeenCalledWith({
      q: 'ankle',
      mode: 'static',
      difficulty: 2,
      familyId: 1,
      sort: 'name',
    });
  });

  it('lists the families with their size and resets', async () => {
    const { onReset, user } = setup();
    expect(screen.getByRole('option', { name: 'hip mobility (1)' })).toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: 'Reset' }));
    expect(onReset).toHaveBeenCalled();
  });
});
