function doGet(e) {
  // Capture parameters sent by the Python script
  var html = HtmlService.createTemplateFromFile('Index');
  
  html.nome = e.parameter.nome || "Colaborador";
  html.mes = e.parameter.mes || "Não informado";
  html.doc = e.parameter.doc || "#";
  html.hash = e.parameter.hash || "Não informado";
  html.pasta = e.parameter.pasta || "";
  html.tipo = e.parameter.tipo || "Documento";

  // Retorna a página renderizada, com permissões para rodar em celulares/iframes
  return html.evaluate()
    .setTitle('Portal de Assinatura - RH PRIME')
    .addMetaTag('viewport', 'width=device-width, initial-scale=1');
}

function processarAssinatura(dados) {
  try {
    var timestamp = new Date().toLocaleString("pt-BR", {timeZone: "America/Sao_Paulo"});
    
    // 1. Salvar na Planilha como backup e registro
    var ss = SpreadsheetApp.getActiveSpreadsheet();
    var sheet = ss.getActiveSheet();
    
    // Configura cabeçalho se a planilha estiver vazia
    if (sheet.getLastRow() === 0) {
      sheet.appendRow(["Data/Hora", "Nome", "Mês/Ref", "Tipo Documento", "Link Original", "Hash Digital", "Pasta Drive", "Declaração", "Assinatura (CPF)", "IP / Dispositivo"]);
      sheet.getRange("A1:J1").setFontWeight("bold").setBackground("#d9d9d9");
    }
    
    sheet.appendRow([
      timestamp,
      dados.nome,
      dados.mes,
      dados.tipo,
      dados.doc,
      dados.hash,
      dados.pasta,
      dados.declaracao,
      dados.assinatura,
      dados.userAgent
    ]);
    
    // 2. Criar PDF do Recibo com validade jurídica
    if (dados.pasta) {
      var folder;
      try {
        folder = DriveApp.getFolderById(dados.pasta);
      } catch (e) {
        Logger.log("Erro ao encontrar a pasta: " + dados.pasta);
      }
      
      if (folder) {
        var docName = "RECIBO - " + dados.tipo + " - " + dados.nome + " - " + dados.mes;
        var doc = DocumentApp.create(docName);
        var body = doc.getBody();
        
        body.appendParagraph("PORTAL DE ASSINATURA - RH PRIME").setHeading(DocumentApp.ParagraphHeading.HEADING1).setAlignment(DocumentApp.HorizontalAlignment.CENTER);
        body.appendParagraph("RECIBO DE VALIDAÇÃO ELETRÔNICA").setHeading(DocumentApp.ParagraphHeading.HEADING2).setAlignment(DocumentApp.HorizontalAlignment.CENTER);
        
        body.appendParagraph("\nDados da Assinatura:");
        body.appendParagraph("Data e Hora: " + timestamp);
        body.appendParagraph("Tipo de Documento: " + dados.tipo);
        body.appendParagraph("Nome do Colaborador: " + dados.nome);
        body.appendParagraph("Referência: " + dados.mes);
        body.appendParagraph("\nTrilha de Auditoria e Integridade:");
        body.appendParagraph("Assinatura Digital (Hash SHA-256 do documento original):");
        body.appendParagraph(dados.hash).setFontFamily("Courier New").setFontSize(10);
        body.appendParagraph("Dados do Dispositivo/IP: " + dados.userAgent).setFontSize(10);
        
        body.appendParagraph("\nDeclaração de Aceite Legal:");
        body.appendParagraph(dados.declaracao).setItalic(true);
        body.appendParagraph("\nChave de Assinatura Eletrônica (5 primeiros dígitos do CPF):");
        body.appendParagraph(dados.assinatura).setBold(true);
        
        body.appendParagraph("\n\n_________________________________________________________").setAlignment(DocumentApp.HorizontalAlignment.CENTER);
        body.appendParagraph("Documento eletrônico validado e assinado digitalmente de acordo com a Lei 14.063/2020.").setAlignment(DocumentApp.HorizontalAlignment.CENTER).setFontSize(9);
        
        doc.saveAndClose();
        
        var docFile = DriveApp.getFileById(doc.getId());
        var pdfBlob = docFile.getAs('application/pdf');
        pdfBlob.setName(docName + ".pdf");
        
        folder.createFile(pdfBlob);
        docFile.setTrashed(true);
      }
    }
    
    return { sucesso: true, mensagem: "Assinatura realizada e registrada com sucesso!" };
    
  } catch (err) {
    Logger.log("Erro ao processar assinatura: " + err);
    return { sucesso: false, mensagem: "Ocorreu um erro no servidor ao registrar a assinatura." };
  }
}

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
        "",                         // E: Link Original
        "",                         // F: Hash Digital
        "",                         // G: Pasta Drive
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
        
        // IP/Assinatura foram omitidos nesta nova estrutura de colunas
        
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

