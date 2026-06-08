// src/tests/integration.test.tsx
import { render, screen } from "@testing-library/react";
import App from "../src/App";

describe("Integration Test: App Rendering", () => {
  it("should render the main app heading", () => {
    render(<App />);
    const heading = screen.getByRole("heading", { name: /Vite \+ React/i });
    expect(heading).toBeInTheDocument();
  });

  it("should render the counter button with initial state", () => {
    render(<App />);
    const button = screen.getByRole("button", { name: /count is 0/i });
    expect(button).toBeInTheDocument();
  });
});
