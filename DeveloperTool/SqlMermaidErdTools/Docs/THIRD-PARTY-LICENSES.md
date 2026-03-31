# Third-Party Licenses

This software includes or depends upon the following third-party components:

## SQLGlot

**Version:** 28.0.0  
**Author:** Toby Mao <toby.mao@gmail.com>  
**Homepage:** https://sqlglot.com/  
**Repository:** https://github.com/tobymao/sqlglot  
**License:** MIT License  

SQLGlot is a comprehensive SQL parser, transpiler, optimizer, and engine that supports 31+ SQL dialects.

### SQLGlot License

```
MIT License

Copyright (c) 2025 Toby Mao

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

---

## Python

**Version:** 3.11  
**License:** Python Software Foundation License (PSF)  
**Homepage:** https://www.python.org/  

This package includes an embedded Python runtime distribution.

The Python Software Foundation License is compatible with the GNU General Public License (GPL) and allows for both commercial and non-commercial use, modification, and distribution.

Full Python license: https://docs.python.org/3/license.html

---

---

## Mermaid.js

**Creator:** Knut Sveidqvist  
**Homepage:** https://mermaid.js.org/  
**Repository:** https://github.com/mermaid-js/mermaid  
**License:** MIT License  

Mermaid is a JavaScript-based diagramming and charting tool that renders Markdown-inspired text definitions to create and modify diagrams dynamically.

**Our Usage:** This package generates Mermaid ERD syntax that is designed to be rendered by Mermaid.js. While we don't bundle Mermaid.js (it's a JavaScript library), our output is specifically formatted for the Mermaid ERD specification.

**Note:** Mermaid.js is not required to use this package - it only generates text. However, to view the diagrams visually, users will need Mermaid.js or a Mermaid-compatible viewer.

---

## Acknowledgments

We extend our gratitude to:
- **Knut Sveidqvist** and the Mermaid.js community for creating the diagram specification format we target
- **Toby Mao** and the SQLGlot contributors for creating an excellent SQL parsing library
- The **Python Software Foundation** for the Python programming language

---

## Legal Compliance

All bundled components are used in accordance with their respective licenses:

✅ **SQLGlot (MIT)**: Allows commercial use, modification, distribution, and private use.  
✅ **Python (PSF)**: Allows commercial use, modification, and distribution.  
✅ **Our Package (MIT)**: Open source and free for all uses.

### MIT License Requirements

Both our package and SQLGlot use the MIT license, which requires:
1. ✅ Including the copyright notice (done above)
2. ✅ Including the license text (done above)
3. ✅ No warranty disclaimer (included in license)

We comply with all license requirements.

