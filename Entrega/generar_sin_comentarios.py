"""Genera los scripts de Entrega/ sin comentarios a partir de DDL/, SP/ y Reportes/.
Uso (desde la raiz del repo):  python3 Entrega/generar_sin_comentarios.py
Los archivos de Entrega/ no se editan a mano: se regeneran. Cada uno se verifica comparando los
tokens de codigo antes y despues (si cambia algo mas que los comentarios, aborta)."""
import os, re

def scan(src):
    """Devuelve lista de (tipo, texto): 'code', 'str', 'ident', 'lc', 'bc'. Respeta literales, [identificadores] y comentarios de bloque anidados."""
    out=[]; i=0; n=len(src); buf=[]
    def flush():
        if buf: out.append(('code',''.join(buf))); buf.clear()
    while i<n:
        c=src[i]
        if c=="'":
            flush(); j=i+1
            while j<n:
                if src[j]=="'":
                    if j+1<n and src[j+1]=="'": j+=2; continue
                    break
                j+=1
            out.append(('str',src[i:j+1])); i=j+1
        elif c=='[':
            flush(); j=src.index(']',i); out.append(('ident',src[i:j+1])); i=j+1
        elif src.startswith('--',i):
            flush(); j=src.find('\n',i); j=n if j<0 else j
            out.append(('lc',src[i:j])); i=j
        elif src.startswith('/*',i):
            flush(); depth=1; j=i+2
            while j<n and depth:
                if src.startswith('/*',j): depth+=1; j+=2
                elif src.startswith('*/',j): depth-=1; j+=2
                else: j+=1
            assert depth==0,'comentario de bloque sin cerrar'
            out.append(('bc',src[i:j])); i=j
        else:
            buf.append(c); i+=1
    flush(); return out

def quitar(src):
    src=src.replace('\r\n','\n')
    pieces=[]
    for t,x in scan(src):
        if t=='lc': continue
        if t=='bc': pieces.append(' ' if '\n' not in x else '\n'*0+' '); continue
        pieces.append(x)
    txt=''.join(pieces)
    lines=[l.rstrip() for l in txt.split('\n')]
    res=[]; blank=0
    for l in lines:
        if l.strip()=='' :
            blank+=1
            if blank>1: continue
        else: blank=0
        res.append(l)
    while res and res[0].strip()=='' : res.pop(0)
    while res and res[-1].strip()=='' : res.pop()
    return '\n'.join(res)+'\n'

def tokens(src):
    """Tokens de codigo sin comentarios ni espacios, para comparar antes/despues."""
    toks=[]
    for t,x in scan(src.replace('\r\n','\n')):
        if t in('lc','bc'): continue
        if t in('str','ident'): toks.append(x); continue
        toks+=re.findall(r"[A-Za-z_@#\$][\w@#\$]*|\d+(?:\.\d+)?|<>|<=|>=|!=|!!\w+!!|\S",x)
    return toks


ARCHIVOS = [
    ('DDL/Z_Demoras_Objetos.sql',                          '01_DDL_Z_Demoras_Objetos.sql'),
    ('DDL/Z_ItinerarioViaje_KmTeoricos_Decimal.sql',       '02_DDL_Z_ItinerarioViaje_KmTeoricos_Decimal.sql'),
    ('SP/Z_SP_ItinerarioViaje.sql',                        '03_SP_Z_SP_ItinerarioViaje.sql'),
    ('Reportes/Reporte_ItinerarioViaje.sql',               '04_Reporte_ItinerarioViaje.sql'),
    ('Reportes/Reporte_ItinerarioViajeConsolidado.sql',    '05_Reporte_ItinerarioViajeConsolidado.sql'),
    ('Reportes/Reporte_CertificacionViajesUM.sql',         '06_Reporte_CertificacionViajesUM.sql'),
    ('Reportes/Reporte_ResumenViajesFinalizados.sql',      '07_Reporte_ResumenViajesFinalizados.sql'),
    ('Reportes/Reporte_ParteDemorasPorUnidad.sql',         '08_Reporte_ParteDemorasPorUnidad.sql'),
]

def update_reporte(consulta, id_reporte):
    """UPDATE que carga la consulta de un reporte en la tabla Reporte (comillas simples duplicadas)."""
    return "UPDATE Reporte\nSET ConsultaSQL = '" + consulta.rstrip('\n').replace("'", "''") + "'\nWHERE IdReporte = " + str(id_reporte) + ";\n"


if __name__ == '__main__':
    raiz = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    for origen, destino in ARCHIVOS:
        s = open(os.path.join(raiz, origen), encoding='utf-8').read()
        r = quitar(s)
        assert tokens(s) == tokens(r), origen + ': los tokens de codigo cambiaron'
        assert not [x for t, x in scan(r) if t in ('lc', 'bc')], origen + ': quedaron comentarios'
        open(os.path.join(raiz, 'Entrega', destino), 'w', encoding='utf-8', newline='\n').write(r)
        print(destino, len(s.splitlines()), '->', len(r.splitlines()), 'lineas')
    consolidado = open(os.path.join(raiz, 'Entrega', '05_Reporte_ItinerarioViajeConsolidado.sql'), encoding='utf-8').read()
    upd = update_reporte(consolidado, 286)
    assert not [x for t, x in scan(upd) if t in ('lc', 'bc')], 'el UPDATE tiene comentarios'
    open(os.path.join(raiz, 'Entrega', '09_UPDATE_Reporte_286_Consolidado.sql'), 'w', encoding='utf-8', newline='\n').write(upd)
    print('09_UPDATE_Reporte_286_Consolidado.sql', len(upd.splitlines()), 'lineas')
