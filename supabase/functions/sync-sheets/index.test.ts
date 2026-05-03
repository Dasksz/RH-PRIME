import { describe, expect, it, afterEach } from "bun:test";
import { handler } from "./index";

const originalFetch = global.fetch;

describe("sync-sheets handler", () => {
  afterEach(() => {
    global.fetch = originalFetch;
  });

  it("should handle OPTIONS request", async () => {
    const req = new Request("http://localhost", { method: "OPTIONS" });
    const res = await handler(req);
    expect(res.status).toBe(200);
    expect(await res.text()).toBe("ok");
  });

  it("should handle successful sync", async () => {
    const csvContent = "some,valid,csv";
    global.fetch = async () => new Response(csvContent, { status: 200 });

    const req = new Request("http://localhost", { method: "POST" });
    const res = await handler(req);

    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.data).toBeDefined();
    expect(body.data.length).toBe(1);
    expect(body.data[0].nome).toBe("John Doe");
  });

  it("should handle fetch failure", async () => {
    global.fetch = async () => new Response("Not Found", { status: 404, statusText: "Not Found" });

    const req = new Request("http://localhost", { method: "POST" });
    const res = await handler(req);

    expect(res.status).toBe(400);
    const body = await res.json();
    expect(body.error).toBe("Failed to fetch sheet: 404 Not Found");
  });

  it("should handle parsing error (generic error block)", async () => {
    global.fetch = async () => new Response("FAIL", { status: 200 });

    const req = new Request("http://localhost", { method: "POST" });
    const res = await handler(req);

    expect(res.status).toBe(400);
    const body = await res.json();
    expect(body.error).toBe("Mocked parsing error");
  });
});
