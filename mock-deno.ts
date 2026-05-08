import { mock } from "bun:test";

export const mockParse = mock(() => []);

mock.module("https://deno.land/std@0.168.0/http/server.ts", () => {
  return {
    serve: () => {}
  };
});

mock.module("https://deno.land/std@0.168.0/encoding/csv.ts", () => {
  return {
    parse: mockParse
  };
});
