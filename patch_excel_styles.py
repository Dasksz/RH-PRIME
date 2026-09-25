with open("admin.html", "r", encoding="utf-8") as f:
    content = f.read()

# Replace handleExportModeloColaboradores styling logic
old_colab_export = """          // Set column widths
          ws["!cols"] = headers.map(() => ({ wch: 28 }));

          const wb = XLSX.utils.book_new();"""

new_colab_export = """          // Header row (row 0) and example row (row 1) styling
          headers.forEach((_, colIdx) => {
            const headerCellRef = XLSX.utils.encode_cell({ r: 0, c: colIdx });
            if (ws[headerCellRef]) {
              ws[headerCellRef].s = {
                font: { bold: true, color: { rgb: "FFFFFF" }, name: "Calibri", sz: 11 },
                fill: { fgColor: { rgb: "002060" } },
                alignment: { vertical: "center", horizontal: "center" }
              };
            }

            const exampleCellRef = XLSX.utils.encode_cell({ r: 1, c: colIdx });
            if (ws[exampleCellRef]) {
              ws[exampleCellRef].s = {
                font: { italic: true, color: { rgb: "7F7F7F" }, name: "Calibri", sz: 9 },
                alignment: { vertical: "center", horizontal: "left" }
              };
            }
          });

          // Set column widths
          ws["!cols"] = headers.map(() => ({ wch: 28 }));

          const wb = XLSX.utils.book_new();"""

content = content.replace(old_colab_export, new_colab_export)

# Replace handleExportModeloEmpresas styling logic
old_emp_export = """          ws["!cols"] = [{ wch: 40 }, { wch: 25 }, { wch: 50 }];

          const wb = XLSX.utils.book_new();"""

new_emp_export = """          headers.forEach((_, colIdx) => {
            const headerCellRef = XLSX.utils.encode_cell({ r: 0, c: colIdx });
            if (ws[headerCellRef]) {
              ws[headerCellRef].s = {
                font: { bold: true, color: { rgb: "FFFFFF" }, name: "Calibri", sz: 11 },
                fill: { fgColor: { rgb: "002060" } },
                alignment: { vertical: "center", horizontal: "center" }
              };
            }

            const exampleCellRef = XLSX.utils.encode_cell({ r: 1, c: colIdx });
            if (ws[exampleCellRef]) {
              ws[exampleCellRef].s = {
                font: { italic: true, color: { rgb: "7F7F7F" }, name: "Calibri", sz: 9 },
                alignment: { vertical: "center", horizontal: "left" }
              };
            }
          });

          ws["!cols"] = [{ wch: 40 }, { wch: 25 }, { wch: 50 }];

          const wb = XLSX.utils.book_new();"""

content = content.replace(old_emp_export, new_emp_export)

with open("admin.html", "w", encoding="utf-8") as f:
    f.write(content)

print("Excel styles applied in admin.html!")
