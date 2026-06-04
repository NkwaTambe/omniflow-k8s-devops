// src/tests/integration.test.ts
import { render, screen } from "@testing-library/react";
import App from "../src/App";

describe("Integration Test: App Rendering", () => {
  it("should render the main title", () => {
    render(<App />);
    const heading = screen.getByRole("heading", { name: /OmniFlow/i });
    expect(heading).toBeInTheDocument();
  });
});
