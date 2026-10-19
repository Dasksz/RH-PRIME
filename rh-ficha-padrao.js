/* Modelo de ficha/termo preservado do Controle de Entregas anterior. */
(function(global){
 function render(emp, items, empresaInfo, returnMode, hasDeliveries) {
          const formatShortDate = (rawDate) => {
            if (!rawDate) return "";
            const str = String(rawDate).trim();
            if (/^\d{4}-\d{2}-\d{2}$/.test(str)) {
              const [y, m, d] = str.split("-");
              return `${d}/${m}/${y}`;
            }
            if (/^\d{2}\/\d{2}\/\d{4}$/.test(str)) {
              return str;
            }
            const parsed = new Date(str);
            if (!isNaN(parsed.getTime())) {
              const d = String(parsed.getDate()).padStart(2, "0");
              const m = String(parsed.getMonth() + 1).padStart(2, "0");
              const y = parsed.getFullYear();
              return `${d}/${m}/${y}`;
            }
            return str;
          };
          const empNome = empresaInfo?.nome || "";
          const empCnpj = empresaInfo?.cnpj || "";
          const empEnd =
            empresaInfo?.endereco ||
            "";

          // Cabeçalho e termos do modelo original.
          const generateTableHeaders = () => `
            <table style="width: 100%; border-collapse: collapse; text-align: center;">
                <thead style="display: table-header-group;">
                    <tr>
                        <th colspan="6" style="background-color: #003399; color: white; text-align: center; font-weight: bold; padding: 3px; border: 1px solid black;">
                            CONTROLE DE EQUIPAMENTO DE PROTEÇÃO INDIVIDUAL - EPI
                        </th>
                    </tr>
                    <tr>
                        <th colspan="6" style="background-color: #e0e0e0; text-align: center; font-weight: bold; padding: 3px; border: 1px solid black;">
                            EQUIPAMENTOS DE PROTEÇÃO INDIVIDUAL RECEBIDOS:
                        </th>
                    </tr>
                    <tr style="font-weight: bold; page-break-inside: avoid;">
                        <th style="border: 1px solid black; padding: 4px; width: 12%;">DATA DE<br>ENTREGA</th>
                        <th style="border: 1px solid black; padding: 4px; width: 42%;">DESCRIÇÃO/ MATERIAL</th>
                        <th style="border: 1px solid black; padding: 4px; width: 12%;">C.A. Nº</th>
                        <th style="border: 1px solid black; padding: 4px; width: 8%;">QTD.</th>
                        <th style="border: 1px solid black; padding: 4px; width: 13%;">DATA DE<br>DEVOLUÇÃO</th>
                        <th style="border: 1px solid black; padding: 4px; width: 13%;">MOTIVO DA<br>DEVOLUÇÃO</th>
                    </tr>
                </thead>
                <tbody>
          `;

          // Add the layout HTML
          // Pagination logic: first page max 5 items, subsequent pages max 15 items.
          const hasReturns = returnMode !== "none";
          const firstPageLimit = hasReturns && hasDeliveries ? 3 : 5;
          const subsequentPageLimit = 15;

          let pagesHtml = "";
          let currentItemIndex = 0;
          let pageNum = 1;

          while (currentItemIndex < items.length || currentItemIndex === 0) {
            const isFirstPage = pageNum === 1;
            const limit = isFirstPage ? firstPageLimit : subsequentPageLimit;
            const chunk = items.slice(
              currentItemIndex,
              currentItemIndex + limit,
            );

            let pageContent = isFirstPage
              ? `
                        <!-- Header -->
                        <div style="border: 1px solid black; display: flex; text-align: center; font-weight: bold; margin-bottom: 5px;">
                            <div style="flex: 1; padding: 10px; border-right: 1px solid black; display: flex; flex-direction: column; justify-content: center; align-items: center;">
                                <div style="font-size: 14px;">${empNome}</div>
                                <div>CNPJ: ${empCnpj}</div>
                                <div>Endereço: ${empEnd}</div>
                            </div>
                            <div style="flex: 1; padding: 10px; display: flex; align-items: center; justify-content: center; font-size: 16px;">
                                FICHA INDIVIDUAL DE FARDAMENTO E EQUIPAMENTO DE PROTEÇÃO INDIVIDUAL – E.P.I.
                            </div>
                        </div>

                        <!-- Employee Info -->
                        <div style="border: 1px solid black; margin-bottom: 5px;">
                            <div style="display: flex; border-bottom: 1px solid black; padding: 5px;">
                                <div style="flex: 3;"><strong>NOME:</strong> ${emp.nome || ""}</div>
                                <div style="flex: 1;"><strong>CPF:</strong> ${emp.cpf || ""}</div>
                                <div style="flex: 1;"><strong>DATA ADMISSÃO:</strong> ${emp.admissao || ""}</div>
                            </div>
                            <div style="display: flex; padding: 5px;">
                                <div style="flex: 1;"><strong>SETOR:</strong> ${emp.setor || ""}</div>
                                <div style="flex: 2;"><strong>FUNÇÃO:</strong> ${emp.cargo || ""}</div>
                                <div style="flex: 1;"><strong>UNIDADE:</strong> ${emp.unidade || ""}</div>
                            </div>
                        </div>

                        <div style="font-size: 9px; margin-bottom: 5px;">
                            NR 6.1 Para os fins de aplicação desta norma Regulamentadora – NR, considera-se <strong>Equipamento de proteção Individual – EPI</strong> é todo dispositivo de uso individual, de fabricação nacional ou estrangeira, destinado a proteger a saúde e a integridade física do trabalhador.
                        </div>

                        <div style="display: flex; font-size: 9px; margin-bottom: 5px; border-top: 1px solid #ccc; border-bottom: 1px solid #ccc; padding: 5px 0;">
                            <div style="flex: 1; padding-right: 10px; border-right: 1px solid #ccc;">
                                <strong>Obrigações do Empregador</strong><br>
                                <strong>6.6.1 Cabe ao empregador quanto ao EPI:</strong><br>
                                a) adquirir o adequado ao risco de cada atividade;<br>
                                b) exigir seu uso;<br>
                                c) fornecer ao trabalhador somente o aprovado pelo órgão nacional competente em matéria de segurança e saúde no trabalho;<br>
                                d) orientar e treinar o trabalhador sobre o uso adequado, guarda e conservação;
                            </div>
                            <div style="flex: 1; padding-left: 10px;">
                                <strong>Obrigações dos Colaboradores</strong><br>
                                <strong>6.7.1. Cabe ao empregado quanto ao EPI</strong><br>
                                <strong>a) usar, utilizando-o apenas para a finalidade a que se destina;</strong><br>
                                <strong>b) responsabilizar-se pela guarda e conservação;</strong><br>
                                <strong>c) comunicar ao empregador qualquer alteração que o torne impróprio para uso;</strong><br>
                                <strong>d) cumprir as determinações do empregador sobre o uso adequado.</strong>
                            </div>
                        </div>

                        <!-- Term -->
                        <div style="border: 1px solid black; padding: 5px; color: red; margin-bottom: 5px;">
                            <strong>Termo de Responsabilidade</strong><br>
                            <span style="color: black; font-size: 9px;">
                                Recebi, da empresa ${empNome}., os EPI´S adequados abaixo, os quais desde já me comprometo sempre usar na execução de minhas tarefas, zelando pela sua perfeita guarda e conservação, uso e funcionamento de acordo com as orientações e treinamentos recebidos da CIPA e/ou SESMT, assumindo também o compromisso de devolvê-lo quando solicitado ou em ocasião de rescisão de meu contrato de trabalho.<br>
                                Estou ciente e de pleno acordo que o não cumprimento das condições estabelecidas, acarretará, além de aplicações de penas disciplinares, inclusive rescisão de meu contrato laboral, outras sanções previstas em lei, em especial nas constantes na NR 06, portaria 3.214 de 08/06/1978, do Ministério do Trabalho.<br>
                                Declaro, também, que estou ciente das disposições do Art. 462 e § 1º da CLT, e autorizo o desconto salarial proporcional ao custo de reparação do dano por mim causado aos EPIs.
                            </span>
                        </div>
             `
              : "";

            // Build table
            let tableContent = `
                ${generateTableHeaders()}
                ${chunk
                  .map((item) => {
                    const dStr = formatShortDate(item.dataEntrega);
                    const devDateStr = formatShortDate(item.dataDevolucao);
                    const motivoStr = item.motivoDevolucao || "";

                    return `
                        <tr style="page-break-inside: avoid;">
                            <td style="border: 1px solid black; padding: 6px 3px;">${dStr}</td>
                            <td style="border: 1px solid black; padding: 6px 3px; text-align: left;">${item.nomeItem}</td>
                            <td style="border: 1px solid black; padding: 6px 3px;">${item.ca || ""}</td>
                            <td style="border: 1px solid black; padding: 6px 3px;">${item.qtd}</td>
                            <td style="border: 1px solid black; padding: 6px 3px;">${devDateStr}</td>
                            <td style="border: 1px solid black; padding: 6px 3px;">${motivoStr}</td>
                        </tr>
                    `;
                  })
                  .join("")}
                </tbody>
            </table>
             `;

            const isLastPage = currentItemIndex + limit >= items.length || items.length === 0;

            let termTitle = "Termo de Verificação";
            let termText = "Declaro ciência das movimentações e do saldo de equipamentos relacionados nesta ficha, conforme suas datas, motivos e quantidades. Baixas por perda ou extravio não representam devolução física.";
            if (returnMode === "current" && hasDeliveries) {
              termTitle = "Termo de Movimentação e Responsabilidade de EPI";
              termText = "Declaro que conferi os materiais relacionados nesta ficha e confirmo a devolução dos itens indicados para devolução e o recebimento dos itens indicados como entregues, conforme as datas, quantidades e demais informações registradas. Responsabilizo-me pela guarda e conservação dos itens recebidos.";
            } else if (returnMode === "current") {
              termTitle = "Termo de Movimentação e Responsabilidade de EPI";
              termText = "Declaro que conferi os materiais relacionados nesta ficha e confirmo a devolução dos itens indicados, conforme as datas, quantidades e demais informações registradas.";
            } else if (returnMode === "history" && hasDeliveries) {
              termTitle = "Termo de Movimentação e Responsabilidade de EPI";
              termText = "Declaro que conferi e estou de acordo com as movimentações registradas nesta ficha, incluindo o histórico de devoluções com suas respectivas datas e informações. Confirmo o recebimento dos itens registrados como entregues, nas quantidades e condições indicadas, e responsabilizo-me pela guarda e conservação dos itens que permanecem comigo.";
            } else if (returnMode === "history") {
              termTitle = "Termo de Movimentação e Responsabilidade de EPI";
              termText = "Declaro ciência das movimentações registradas nesta ficha e do histórico de devoluções anteriormente realizadas, com suas respectivas datas, quantidades e motivos.";
            } else if (hasDeliveries) {
              termTitle = "Termo de Recebimento de EPI";
              termText = "Declaro que conferi os materiais relacionados nesta ficha e confirmo o recebimento dos itens registrados como entregues, nas datas, quantidades e condições informadas. Responsabilizo-me pela guarda e conservação dos itens que permanecem comigo.";
            }
            const signaturesBlock = isLastPage ? `
                <div class="signatures" style="margin-top: 12px; border: 1px solid black; padding: 8px; page-break-inside: avoid;">
                    <div style="border: 1px solid #a0a0a0; padding: 10px; background-color: #fafafa; display: flex; flex-direction: column; justify-content: space-between;">
                        <div>
                            <strong style="font-size: 10px; color: #002060; display: block; margin-bottom: 4px; text-transform: uppercase;">${termTitle}</strong>
                            <p style="font-size: 9px; margin: 0; line-height: 1.3; color: #111;">${termText}</p>
                        </div>
                        <div style="display: flex; justify-content: space-between; align-items: flex-end; margin-top: 25px;">
                            <div style="font-size: 9px; font-weight: bold;">Data: ____/____/________</div>
                            <div style="text-align: center; width: 50%;">
                                <div style="border-bottom: 1px solid black; width: 100%; margin-bottom: 4px;"></div>
                                <span style="font-size: 8.5px; font-weight: bold; text-transform: uppercase;">${hasReturns || hasDeliveries ? "Assinatura do Colaborador (Entrega e/ou Devolução)" : "Assinatura do Colaborador"}</span>
                            </div>
                        </div>
                    </div>
                </div>
              ` : "";

            pagesHtml += `
                <div style="${!isFirstPage ? "page-break-before: always; margin-top: 20px;" : ""}">
                    ${pageContent}
                    ${tableContent}
                    ${signaturesBlock}
                </div>
             `;

            currentItemIndex += limit;
            pageNum++;

            // break if array is empty and we rendered the first empty page
            if (items.length === 0) break;
          }

          return `
            <div class="rh-equipment-standard-pdf" style="width: 1080px; background: white; font-family: Arial, Helvetica, sans-serif; padding: 20px; box-sizing: border-box; color: black; font-size: 10px; line-height: 1.3; letter-spacing: 0.2px; word-spacing: 1px; text-rendering: optimizeLegibility;">
                ${pagesHtml}
            </div>
          `;


 }
 global.RHFichaPadrao={render};
})(window);
