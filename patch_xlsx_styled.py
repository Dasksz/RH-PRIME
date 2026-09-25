with open("admin.html", "r", encoding="utf-8") as f:
    content = f.read()

# Replace CDN script tag
old_cdn = '<script src="https://cdn.jsdelivr.net/npm/xlsx@0.18.5/dist/xlsx.full.min.js"></script>'
new_cdn = '<!-- XLSX with Cell Styles support (xlsx-js-style) -->\n    <script src="https://cdn.jsdelivr.net/npm/xlsx-js-style@1.2.0/dist/xlsx.bundle.js"></script>'

if old_cdn in content:
    content = content.replace(old_cdn, new_cdn)

with open("admin.html", "w", encoding="utf-8") as f:
    f.write(content)

print("CDN script replaced in admin.html!")
