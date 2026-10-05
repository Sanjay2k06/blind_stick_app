import fitz

doc = fitz.open('report/thrisha report (1).pdf')
sample_pages = [0, 1, 2, 3, 4, 8, 12, 15, 21, 27, 29, 37, 39, 41, 42]

with open('pdf_layout_analysis.txt', 'w', encoding='utf-8') as out:
    for pno in range(len(doc)):
        page = doc[pno]
        rect = page.rect
        out.write(f"\n==================== PAGE {pno+1} ({rect.width:.1f} x {rect.height:.1f}) ====================\n")
        blocks = page.get_text('dict')['blocks']
        for b in blocks:
            if 'lines' in b:
                for l in b['lines']:
                    line_spans = []
                    for s in l['spans']:
                        t = s['text'].strip()
                        if t:
                            line_spans.append(f"[{s['font']} {s['size']:.1f}pt @ ({s['bbox'][0]:.1f},{s['bbox'][1]:.1f})]: {t}")
                    if line_spans:
                        out.write('  ' + ' | '.join(line_spans) + '\n')
            elif 'image' in b:
                out.write(f"  [IMAGE: bbox=({b['bbox'][0]:.1f}, {b['bbox'][1]:.1f}, {b['bbox'][2]:.1f}, {b['bbox'][3]:.1f}), width={b.get('width')}, height={b.get('height')}]\n")

print("Analyzed", len(doc), "pages into pdf_layout_analysis.txt")
