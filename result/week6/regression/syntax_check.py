from pathlib import Path
import ast
root=Path(r'D:\Desktop\DB\DB_lab\week6')
paths=sorted(root.glob('*.py'))
for p in paths:
 ast.parse(p.read_text(encoding='utf-8-sig'),filename=str(p))
print('PYTHON_AST_PASS',len(paths),'files')
