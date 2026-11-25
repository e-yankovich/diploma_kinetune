import { screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it } from 'vitest';
import { families } from '../test/fixtures';
import { jsonResponse, mockFetch, renderAt } from '../test/utils';
import { FamiliesPage } from './FamiliesPage';

describe('FamiliesPage', () => {
  it('lists the families and opens the filtered library', async () => {
    mockFetch([[/\/families/, () => jsonResponse(families)]]);
    renderAt('/families', '/families', <FamiliesPage />);
    expect(await screen.findByText('13 exercises')).toBeInTheDocument();
    expect(screen.getByText('1 exercise')).toBeInTheDocument();
    await userEvent.click(screen.getByRole('button', { name: /ankle mobility/ }));
    expect(screen.getByText('other page')).toBeInTheDocument();
  });
});
