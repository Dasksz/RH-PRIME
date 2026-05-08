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
    // Override fetch to explicitly mock response object with ok: false to ensure we hit the
    // `if (!response.ok)` block which throws a specific Error. Note that just mocking Response
    // object natively in bun test for 500 status may implicitly handle OK.
    global.fetch = mock(() => {
        return Promise.resolve({
            ok: false,
            status: 500,
            statusText: "Internal Server Error",
            text: () => Promise.resolve("Internal Server Error")
        } as unknown as Response);
    });

    const req = new Request("http://localhost");
    const response = await handler(req);

    expect(response.status).toBe(400);
    const body = await response.json();
    expect(body.error).toContain("Failed to fetch sheet: 500 Internal Server Error");
  });

  test("should handle empty CSV string and return empty data array", async () => {
    // Mock fetch to return a 200 response with empty string
    global.fetch = mock(() => Promise.resolve(new Response("")));

    const req = new Request("http://localhost");
    const response = await handler(req);

    expect(response.status).toBe(200);
    const body = await response.json();
    expect(body).toEqual({ data: [] });
  });
});

describe("sync-sheets valid behaviors", () => {
  let originalFetch: typeof global.fetch;

  beforeAll(() => {
    originalFetch = global.fetch;
  });

  afterAll(() => {
    global.fetch = originalFetch;
  });

  test("should handle OPTIONS request and return CORS headers", async () => {
    const req = new Request("http://localhost", {
      method: "OPTIONS",
      headers: {
        origin: "https://gcksbfstheavpfgcdndb.supabase.co"
      }
    });

    const response = await handler(req);
    expect(response.status).toBe(200);
    expect(await response.text()).toBe("ok");
    expect(response.headers.get("access-control-allow-origin")).toBe("https://gcksbfstheavpfgcdndb.supabase.co");
    expect(response.headers.get("access-control-allow-headers")).toContain("authorization");
  });

  test("should return empty data array when CSV has no valid data rows", async () => {
    // Mock fetch to return only header row
    global.fetch = mock(() => Promise.resolve(new Response("Admissão,Nome Completo do Funcionário,Função,Data Última Entrega (EPI),Link Comprovante (EPI),Data Última Entrega (Fardamento),Link Comprovante (Fardamento),Check / Validação")));

    const req = new Request("http://localhost");
    const response = await handler(req);

    expect(response.status).toBe(200);
    const body = await response.json();
    expect(body).toEqual({ data: [] });
  });

  test("should correctly map data rows to employees including status and initials logic", async () => {
    const now = new Date();
    // Format date as MM/DD/YYYY
    const todayStr = `${now.getMonth() + 1}/${now.getDate()}/${now.getFullYear()}`;

    // Row 1: Alice Silva, recent dates -> em_dia, initials AS
    // Row 2: Bob Builder, old dates -> vencido, initials BB
    // Row 3: Charlie, missing dates -> pendente, initials CH
    const csvData = [
      "Admissão,Nome Completo do Funcionário,Função,Data Última Entrega (EPI),Link Comprovante (EPI),Data Última Entrega (Fardamento),Link Comprovante (Fardamento),Check / Validação",
      `01/01/2023,Alice Silva,Developer,${todayStr},link_epi_1,${todayStr},link_fard_1,OK`,
      "01/01/2020,Bob Builder,Engineer,01/01/2020,link_epi_2,01/01/2020,link_fard_2,OK",
      "01/01/2025,Charlie,Manager,,,,,",
      "01/01/2025,,,missing_name,,,,", // Invalid row (missing name/empty string usually filtered out)
    ].join('\n');

    global.fetch = mock(() => Promise.resolve(new Response(csvData)));

    const req = new Request("http://localhost");
    const response = await handler(req);

    expect(response.status).toBe(200);
    const body = await response.json();

    const employees = body.data;
    expect(employees.length).toBe(3); // The 4th row has empty name which becomes '' but column 1 is empty so filtered by `row[1].trim() !== ''`

    // Row 1 assertions
    expect(employees[0].nome).toBe("Alice Silva");
    expect(employees[0].avatar).toBe("AS");
    expect(employees[0].epi.status).toBe("em_dia");
    expect(employees[0].fardamento.status).toBe("em_dia");

    // Row 2 assertions
    expect(employees[1].nome).toBe("Bob Builder");
    expect(employees[1].avatar).toBe("BB");
    expect(employees[1].epi.status).toBe("vencido");
    expect(employees[1].fardamento.status).toBe("vencido");

    // Row 3 assertions
    expect(employees[2].nome).toBe("Charlie");
    expect(employees[2].avatar).toBe("CH");
    expect(employees[2].epi.status).toBe("pendente");
    expect(employees[2].fardamento.status).toBe("pendente");
  });
});
