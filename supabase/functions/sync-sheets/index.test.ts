import { expect, test, mock, describe, beforeAll, afterAll, spyOn } from "bun:test";
import { handler } from "./index.ts";

describe("sync-sheets error handling", () => {
  let originalFetch: typeof global.fetch;
  let consoleErrorSpy: ReturnType<typeof spyOn>;
  let consoleLogSpy: ReturnType<typeof spyOn>;

  beforeAll(() => {
    originalFetch = global.fetch;
    consoleErrorSpy = spyOn(console, 'error').mockImplementation(() => {});
    consoleLogSpy = spyOn(console, 'log').mockImplementation(() => {});
  });

  afterAll(() => {
    global.fetch = originalFetch;
    consoleErrorSpy.mockRestore();
    consoleLogSpy.mockRestore();
  });

  test("should catch errors and return status 400 with error message", async () => {
    // Mock fetch to throw an error
    global.fetch = mock(() => Promise.reject(new Error("Simulated network failure")));

    const req = new Request("http://localhost");
    const response = await handler(req);

    // Verify response status
    expect(response.status).toBe(400);

    // Verify response headers
    expect(response.headers.get("content-type")).toBe("application/json");

    // Verify response body
    const body = await response.json();
    expect(body).toEqual({ error: "Simulated network failure" });

    // Verify console.error was called
    expect(consoleErrorSpy).toHaveBeenCalled();
  });

  test("should catch non-ok fetch response and return status 400", async () => {
    // Mock fetch to return a 500 response
    global.fetch = mock(() => Promise.resolve(new Response("Internal Server Error", { status: 500, statusText: "Internal Server Error" })));

    const req = new Request("http://localhost");
    const response = await handler(req);

    expect(response.status).toBe(400);
    const body = await response.json();
    expect(body.error).toContain("Failed to fetch sheet: 500 Internal Server Error");
  });
});

describe("sync-sheets data parsing edge cases", () => {
  let originalFetch: typeof global.fetch;
  let consoleLogSpy: ReturnType<typeof spyOn>;

  beforeAll(() => {
    originalFetch = global.fetch;
    consoleLogSpy = spyOn(console, 'log').mockImplementation(() => {});
  });

  afterAll(() => {
    global.fetch = originalFetch;
    consoleLogSpy.mockRestore();
  });

  test("should handle missing columns or empty name without crashing", async () => {
    // Create a specific mock parse return value locally for this test
    const { mockParse } = await import("../../../mock-deno.ts");
    mockParse.mockReturnValue([
      ["Admissão", "Nome Completo", "Função", "EPI Data", "EPI Link", "Fardamento Data", "Fardamento Link"],
      // Row missing most columns
      ["01/01/2023", "   "],
      // Missing name column entirely
      ["01/01/2023"],
      // Row where only name has a value
      ["", "A"],
      ["", "John Doe"],
    ]);

    global.fetch = mock(() => Promise.resolve(new Response("fake csv")));

    const req = new Request("http://localhost");
    const res = await handler(req);
    const json = await res.json();

    expect(res.status).toBe(200);

    // The filter skips rows where row[1] is falsy or just whitespace
    expect(json.data.length).toBe(2);

    expect(json.data[0].nome).toBe("A");
    expect(json.data[0].avatar).toBe("A");

    expect(json.data[1].nome).toBe("John Doe");
    expect(json.data[1].avatar).toBe("JD");
  });
});
