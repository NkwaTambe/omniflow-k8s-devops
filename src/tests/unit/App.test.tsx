import { render, screen, fireEvent } from '@testing-library/react';
import App from '@/App';

describe('App Component', () => {
  it('renders initial count and increments on button click', () => {
    render(<App />);
    const button = screen.getByRole('button', { name: /count is/i });
    expect(button).toBeInTheDocument();
    expect(button).toHaveTextContent('count is 0');
    fireEvent.click(button);
    expect(button).toHaveTextContent('count is 1');
  });
});
