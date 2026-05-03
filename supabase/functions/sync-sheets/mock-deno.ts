import { mock } from "bun:test";

mock.module("https://deno.land/std@0.168.0/http/server.ts", () => ({
  serve: () => {},
}));

mock.module("https://deno.land/std@0.168.0/encoding/csv.ts", () => ({
  parse: (csv: string, options: any) => {
    if (csv === "FAIL") throw new Error("Mocked parsing error");
    if (csv === "EMPTY") return [];
    return [
        ["Admissão", "Nome Completo", "Função", "EPI Data", "EPI Link", "Fardamento Data", "Fardamento Link", "Check"],
        ["2023-01-01", "John Doe", "Worker", "01/01/2023", "http://link", "01/01/2023", "http://link", "OK"]
    ];
  },
}));
