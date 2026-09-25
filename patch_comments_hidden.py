with open("admin.html", "r", encoding="utf-8") as f:
    content = f.read()

# Replace comment assignment in handleExportModeloColaboradores and handleExportModeloEmpresas
old_code = """          comments.forEach((comment, colIdx) => {
            const cellAddress = XLSX.utils.encode_cell({ r: 0, c: colIdx });
            if (!ws[cellAddress]) return;
            ws[cellAddress].c = [{ a: "PRIME RH", t: comment }];
          });"""

new_code = """          comments.forEach((comment, colIdx) => {
            const cellAddress = XLSX.utils.encode_cell({ r: 0, c: colIdx });
            if (!ws[cellAddress]) return;
            ws[cellAddress].c = [{ a: "PRIME RH", t: comment, hidden: true }];
            ws[cellAddress].c.hidden = true;
          });"""

content = content.replace(old_code, new_code)

with open("admin.html", "w", encoding="utf-8") as f:
    f.write(content)

print("Comments patched to hidden in admin.html")
