/**
 * Configurações Principais
 */

/**
 * Função doPost(e)
 * Recebe chamadas POST.
 * Pode ser o robô em Python registrando um novo documento enviado.
 * Ou pode ser o Webhook da ZapSign informando que o documento foi assinado.
 */
function doPost(e) {
  try {
    const sheet = SpreadsheetApp.getActiveSpreadsheet().getActiveSheet();
    const data = JSON.parse(e.postData.contents);

    // Ação: Registrar novo documento pendente (enviado pelo Python/Robô)
    if (data.action === "register") {
      // Usando as colunas mostradas na imagem do cliente:
      // A: Data/Hora | B: Nome | C: Mês/Ref | D: Tipo Documento | E: Pasta Drive | F: Declaração | G: Assinatura (CPF IP / Dispositivo)
      // Adicionaremos colunas necessárias à direita ou utilizaremos as existentes com semântica adaptada
      // Vamos assumir que a planilha receberá Novas Colunas à direita para a Integração ZapSign.
      // H: Document ID ZapSign | I: Status (Pendente/Assinado) | J: Link Assinatura | K: Telefone n8n

      const rowData = [
        new Date(),                 // A: Data/Hora
        data.nome,                  // B: Nome
        data.mes_ref || "",         // C: Mês/Ref
        data.tipo_documento || "",  // D: Tipo Documento
        "",                         // E: Pasta Drive (pode ficar vazio para Ativos agora)
        "",                         // F: Declaração (Vazio inicial)
        "",                         // G: Assinatura (Vazio inicial)
        data.document_id,           // H: Document ID ZapSign
        "Pendente",                 // I: Status
        data.link_assinatura,       // J: Link Assinatura
        data.telefone               // K: Telefone
      ];

      sheet.appendRow(rowData);

      return ContentService.createTextOutput(JSON.stringify({ status: "success", message: "Registrado como Pendente" }))
        .setMimeType(ContentService.MimeType.JSON);
    }

    // Ação: Webhook da ZapSign (Documento Assinado)
    if (data.event_type === "doc_signed" || data.event_type === "doc_completed") {
      const docToken = data.doc.token; // ou data.doc.id dependendo do webhook

      // Procurar o documento na planilha (assumindo Document ID na coluna H / index 7)
      const rows = sheet.getDataRange().getValues();
      let rowIndex = -1;

      for (let i = 1; i < rows.length; i++) {
        if (rows[i][7] === docToken) {
          rowIndex = i + 1;
          break;
        }
      }

      if (rowIndex !== -1) {
        // Atualizar Status (coluna I / index 9)
        sheet.getRange(rowIndex, 9).setValue("Assinado");

        // Se quiser salvar o IP/Assinatura na coluna G, como era no antigo:
        let assinaturaStr = "Assinado via ZapSign";
        if (data.signer && data.signer.ip) {
            assinaturaStr += ` (IP: ${data.signer.ip})`;
        }
        sheet.getRange(rowIndex, 7).setValue(assinaturaStr);

        return ContentService.createTextOutput(JSON.stringify({ status: "success", message: "Status atualizado para Assinado" }))
          .setMimeType(ContentService.MimeType.JSON);
      } else {
        return ContentService.createTextOutput(JSON.stringify({ status: "error", message: "Documento não encontrado na planilha" }))
          .setMimeType(ContentService.MimeType.JSON);
      }
    }

    return ContentService.createTextOutput(JSON.stringify({ status: "error", message: "Ação não reconhecida" }))
      .setMimeType(ContentService.MimeType.JSON);

  } catch (error) {
    return ContentService.createTextOutput(JSON.stringify({ status: "error", message: error.toString() }))
      .setMimeType(ContentService.MimeType.JSON);
  }
}

/**
 * Função enviarLembretes()
 * Deve ser configurada num Trigger Temporal (Acionador) para rodar 1x ao dia.
 */
function enviarLembretes() {
  const sheet = SpreadsheetApp.getActiveSpreadsheet().getActiveSheet();
  const rows = sheet.getDataRange().getValues();
  const urlWebhookN8n = "https://rhprime.app.n8n.cloud/webhook/holerites"; // Mesma URL do webhook n8n base

  const now = new Date();

  // Ignora cabeçalho (linha 0 do array)
  for (let i = 1; i < rows.length; i++) {
    const dataCriacao = new Date(rows[i][0]); // Coluna A: Data/Hora
    const nome = rows[i][1];                 // Coluna B: Nome
    const status = rows[i][8];               // Coluna I: Status
    const linkAssinatura = rows[i][9];       // Coluna J: Link Assinatura
    const telefone = rows[i][10];            // Coluna K: Telefone

    // Verifica se passaram mais de 24 horas
    const diffHours = (now - dataCriacao) / (1000 * 60 * 60);

    if (status === "Pendente" && diffHours >= 24) {
      // Lembrete
      const mensagem = `Olá, ${nome}.\nEste é um lembrete amigável do RH PRIME. Identificamos que você ainda não assinou seu documento pendente.\n\nPor favor, acesse o link abaixo para assinar de forma rápida e segura:\n${linkAssinatura}\n\nTenha um excelente dia!`;

      const payload = {
        chatId: telefone,
        caption: mensagem,
        session: "default"
      };

      const options = {
        method: "post",
        contentType: "application/json",
        payload: JSON.stringify(payload)
      };

      try {
        UrlFetchApp.fetch(urlWebhookN8n, options);
      } catch (e) {
        Logger.log("Erro ao enviar lembrete para " + nome + ": " + e.toString());
      }
    }
  }
}
