with open("admin.html", "r", encoding="utf-8") as f:
    code = f.read()

# Add SheetJS script right after Supabase JS
target_script = '<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.39.7/dist/umd/supabase.min.js"></script>'
sheetjs_script = target_script + '\n\n    <!-- SheetJS (XLSX) CDN -->\n    <script src="https://cdn.jsdelivr.net/npm/xlsx@0.18.5/dist/xlsx.full.min.js"></script>'

if target_script in code and "xlsx.full.min.js" not in code:
    code = code.replace(target_script, sheetjs_script)

with open("admin.html", "w", encoding="utf-8") as f:
    f.write(code)

print("SheetJS added to admin.html")
