/* Cartazes mensais gerados no navegador com a lista da página de Colaboradores. */
(function (global) {
  "use strict";

  const azul = "#102847";
  const verde = "#076857";
  const verdeClaro = "#73c5ad";
  const branco = "#ffffff";
  const largura = 1080;
  const modelos = {
    pdf: { altura: 1527, porPagina: 15, escala: 2.3 },
    imagem: { altura: 1350, porPagina: 10, escala: 1 },
  };
  const pdfLibUrl = "https://cdn.jsdelivr.net/npm/pdf-lib@1.17.1/dist/pdf-lib.min.js";
  let carregamentoPdf;

  function carregarPdfLib() {
    if (global.PDFLib?.PDFDocument) return Promise.resolve(global.PDFLib);
    if (!carregamentoPdf) {
      carregamentoPdf = new Promise((resolve, reject) => {
        const script = global.document.createElement("script");
        script.src = pdfLibUrl;
        script.onload = () => {
          global.PDFLib?.PDFDocument ? resolve(global.PDFLib) : reject(new Error("Biblioteca de PDF indisponível."));
        };
        script.onerror = () => reject(new Error("Não foi possível carregar a biblioteca de PDF."));
        global.document.head.appendChild(script);
      }).catch((erro) => {
        carregamentoPdf = null;
        throw erro;
      });
    }
    return carregamentoPdf;
  }

  function dividir(aniversariantes, formato) {
    const porPagina = modelos[formato].porPagina;
    return Array.from({ length: Math.ceil(aniversariantes.length / porPagina) }, (_, indice) =>
      aniversariantes.slice(indice * porPagina, (indice + 1) * porPagina)
    );
  }

  function retangulo(ctx, x, y, largura, altura, cor, raio = 0, borda) {
    ctx.beginPath();
    ctx.roundRect(x, y, largura, altura, raio);
    ctx.fillStyle = cor;
    ctx.fill();
    if (borda) {
      ctx.strokeStyle = borda;
      ctx.lineWidth = 2;
      ctx.stroke();
    }
  }

  function texto(ctx, valor, x, y, tamanho, cor, alinhar = "left", maximo) {
    ctx.font = "700 " + tamanho + "px Arial, sans-serif";
    ctx.textAlign = alinhar;
    ctx.textBaseline = "middle";
    ctx.fillStyle = cor;
    if (maximo) ctx.fillText(valor, x, y, maximo);
    else ctx.fillText(valor, x, y);
  }

  function nome(ctx, valor, x, y, tamanho, maximo) {
    const completo = String(valor || "").trim().replace(/\s+/g, " ");
    ctx.font = "700 " + tamanho + "px Arial, sans-serif";
    if (ctx.measureText(completo).width <= maximo) {
      texto(ctx, completo, x, y, tamanho, azul);
      return;
    }
    const espacos = Array.from(completo.matchAll(/ /g), (m) => m.index);
    const meio = completo.length / 2;
    const corte = espacos.reduce((melhor, posicao) =>
      Math.abs(posicao - meio) < Math.abs(melhor - meio) ? posicao : melhor,
      espacos[0] ?? Math.ceil(meio)
    );
    const linhas = [completo.slice(0, corte), completo.slice(corte).trimStart()];
    const menor = tamanho - 4;
    linhas.forEach((linha, i) => texto(ctx, linha, x, y + (i - 0.5) * menor, menor, azul, "left", maximo));
  }

  function desenhar(pessoas, mes, mesNome, formato, numero, total) {
    const { altura, escala } = modelos[formato];
    const margem = 54;
    const miolo = largura - margem * 2;
    const canvas = global.document.createElement("canvas");
    canvas.width = Math.round(largura * escala);
    canvas.height = Math.round(altura * escala);
    const ctx = canvas.getContext("2d");
    if (!ctx) throw new Error("Não foi possível criar o cartaz.");
    ctx.scale(escala, escala);
    ctx.fillStyle = branco;
    ctx.fillRect(0, 0, largura, altura);
    const tituloMes = mesNome.charAt(0).toLocaleUpperCase("pt-BR") + mesNome.slice(1);

    if (formato === "pdf") {
      retangulo(ctx, margem, 50, miolo, 235, azul, 18);
      retangulo(ctx, margem + 2, 274, miolo - 4, 9, verde, 4);
      texto(ctx, "RH PRIME", 540, 118, 62, branco, "center");
      retangulo(ctx, 439, 164, 202, 5, verdeClaro, 2);
      texto(ctx, "Aniversariantes do mês", 540, 218, 47, branco, "center");
      texto(ctx, tituloMes, 540, 356, 76, verde, "center");
      const alturaLinha = Math.min(148, Math.floor(990 / pessoas.length));
      pessoas.forEach(({ dia, nome: colaborador }, indice) => {
        const y = 425 + indice * alturaLinha;
        texto(ctx, dia + "/" + mes, 86, y + alturaLinha / 2, 36, azul);
        nome(ctx, colaborador, 248, y + alturaLinha / 2, 36, 742);
        retangulo(ctx, 83, y + alturaLinha - 1, 914, 1.5, "#aac8bf");
      });
      retangulo(ctx, margem, 1458, miolo, 3, verde, 1);
      if (total > 1) texto(ctx, "Página " + numero + " de " + total, 540, 1489, 21, azul, "center");
    } else {
      texto(ctx, "RH PRIME", 540, 99, 66, azul, "center");
      retangulo(ctx, 440, 153, 200, 5, verde, 2);
      texto(ctx, "Aniversariantes do mês", 540, 213, 49, azul, "center");
      retangulo(ctx, margem, 276, miolo, 83, verde, 18);
      texto(ctx, tituloMes, 540, 318, 63, branco, "center");
      const passo = Math.min(138, Math.floor(870 / pessoas.length));
      const alturaCartao = Math.min(104, passo - 15);
      pessoas.forEach(({ dia, nome: colaborador }, indice) => {
        const y = 395 + indice * passo;
        retangulo(ctx, margem, y, miolo, alturaCartao, branco, 16, verde);
        retangulo(ctx, margem, y, 206, alturaCartao, verde, [16, 0, 0, 16]);
        texto(ctx, dia + "/" + mes, margem + 103, y + alturaCartao / 2, 40, branco, "center");
        nome(ctx, colaborador, margem + 237, y + alturaCartao / 2, 37, 702);
      });
      if (total > 1) texto(ctx, "Imagem " + numero + " de " + total, 540, 1303, 26, verde, "center");
    }

    return canvas;
  }

  function imagem(pessoas, mes, mesNome, numero, total) {
    const canvas = desenhar(pessoas, mes, mesNome, "imagem", numero, total);
    return new Promise((resolve, reject) => {
      canvas.toBlob((blob) => {
        canvas.width = 0;
        canvas.height = 0;
        if (blob) resolve(blob);
        else reject(new Error("Não foi possível gerar a imagem."));
      }, "image/png");
    });
  }

  async function pdf(paginas, mes, mesNome) {
    const { PDFDocument, PageSizes } = await carregarPdfLib();
    const documento = await PDFDocument.create();
    documento.setTitle("Aniversariantes do mês - " + mesNome);
    documento.setAuthor("RH PRIME");
    for (const [indice, pessoas] of paginas.entries()) {
      const canvas = desenhar(pessoas, mes, mesNome, "pdf", indice + 1, paginas.length);
      const dados = canvas.toDataURL("image/png");
      canvas.width = 0;
      canvas.height = 0;
      const cartaz = await documento.embedPng(dados);
      const pagina = documento.addPage(PageSizes.A4);
      const { width, height } = pagina.getSize();
      pagina.drawImage(cartaz, { x: 0, y: 0, width, height });
    }
    return new Blob([await documento.save()], { type: "application/pdf" });
  }

  global.RHAniversariantes = { dividir, imagem, pdf };
})(window);
