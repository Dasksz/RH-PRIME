import { mock } from "bun:test";

mock.module("https://deno.land/std@0.168.0/http/server.ts", () => {
  return {
    serve: () => {}
  };
});

mock.module("https://deno.land/std@0.168.0/encoding/csv.ts", () => {
  return {
    parse: (data: string) => {
      if (!data) return [];
      return data.split('\n').map(row => row.split(','));
    }
  };
});
