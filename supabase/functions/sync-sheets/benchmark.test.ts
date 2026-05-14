import { handler } from "./index.ts";
import { expect, test, beforeAll, afterAll } from "bun:test";

test("benchmark", async () => {
  const sheetUrl = 'https://docs.google.com/spreadsheets/d/1wJJu3N-lehjZaQw2JtfWLXdss6YbVP1JbfveDzWkGRg/export?format=csv';
  const csvData = "Admissão,Nome Completo do Funcionário,Função,Data Última Entrega (EPI),Link Comprovante (EPI),Data Última Entrega (Fardamento),Link Comprovante (Fardamento),Check / Validação\n01/01/2023,Alice Silva,Developer,03/20/2025,link_epi_1,03/20/2025,link_fard_1,OK";

  let fetchCount = 0;
  // Mock fetch to simulate a 500ms delay
  global.fetch = async (url) => {
    if (url.toString().includes('google.com')) {
      fetchCount++;
      await new Promise(resolve => setTimeout(resolve, 500));
      return new Response(csvData);
    }
    return new Response('ok');
  };

  console.log("Starting benchmark...");

  const start1 = performance.now();
  await handler(new Request("http://localhost"));
  const end1 = performance.now();
  console.log(`First call took: ${(end1 - start1).toFixed(2)}ms, fetchCount: ${fetchCount}`);

  const start2 = performance.now();
  await handler(new Request("http://localhost"));
  const end2 = performance.now();
  console.log(`Second call took: ${(end2 - start2).toFixed(2)}ms, fetchCount: ${fetchCount}`);

  const start3 = performance.now();
  await handler(new Request("http://localhost"));
  const end3 = performance.now();
  console.log(`Third call took: ${(end3 - start3).toFixed(2)}ms, fetchCount: ${fetchCount}`);
});
