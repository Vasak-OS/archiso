#!/usr/bin/env bash
#
# Comprobaciones sobre el perfil del ISO, sin armarlo.
#
# Nacieron de un error que estuvo desde el principio y que nadie vio: el inicio
# automático de tty1 nombraba a un usuario `lynx` que **no existe** en la
# imagen. El de la sesión en vivo es `vasak`. O sea que la consola de rescate
# —la tecla que se aprieta cuando la pantalla queda negra— no daba ninguna
# sesión, y eso es la mitad de por qué el informe de la pantalla negra decía
# «no se cuenta con logs».
#
# Ninguna de estas cosas la puede ver `mkarchiso`: arma la imagen igual y el
# problema recién aparece con el ISO andando en otra máquina. Por eso van acá y
# no en la construcción.
#
# Uso: pruebas/perfil.sh
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

fallos=0
ok()    { printf '  \033[32m✓\033[0m %s\n' "$1"; }
mal()   { printf '  \033[31m✗\033[0m %s\n' "$1"; fallos=$((fallos + 1)); }
tema()  { printf '\n\033[1m%s\033[0m\n' "$1"; }

# ---------------------------------------------------------------------------
tema 'Los usuarios que se nombran existen'

# Un usuario puede llegar al ISO por dos caminos, y los dos valen: escrito en
# el passwd del perfil, o creado por el `sysusers.d` de algún paquete que el
# ISO instala — así aparece `greeter`, que lo crea el propio greetd.
existe_el_usuario() {
    grep -q "^${1}:" airootfs/etc/passwd && return 0

    # Se busca el paquete dueño del `sysusers.d` y se comprueba que el ISO lo
    # instale: o está en la lista, o lo arrastra algo que sí está —`greetd`
    # entra así, como dependencia de `vasakos-desktop`—. Mirar el `getent` de
    # este equipo no serviría: diría que sí por usuarios que acá existen y en la
    # imagen no.
    while IFS= read -r archivo; do
        paquete=$(pacman -Qoq "$archivo" 2>/dev/null) || continue
        grep -qx "$paquete" packages.x86_64 && return 0
        while IFS= read -r quien_lo_pide; do
            grep -qx "$quien_lo_pide" packages.x86_64 && return 0
        done < <(pactree -rlu "$paquete" 2>/dev/null)
    done < <(grep -lE "^u[[:space:]]+${1}([[:space:]]|\$)" /usr/lib/sysusers.d/*.conf 2>/dev/null)

    return 1
}

# `--autologin <alguien>` con un `<alguien>` que no existe es una sesión que
# nunca abre: falla en PAM sin decir nada en pantalla. Se saltean las líneas
# comentadas, porque el comentario que explica el error de ayer nombra al
# usuario de ayer.
while IFS= read -r usuario; do
    if existe_el_usuario "$usuario"; then
        ok "--autologin ${usuario}"
    else
        mal "--autologin ${usuario}: no existe ni en el passwd del perfil ni en un sysusers.d del ISO"
    fi
done < <(grep -rh -vE '^[[:space:]]*#' airootfs/etc/systemd/ 2>/dev/null \
    | grep -oP '(?<=--autologin )[A-Za-z0-9_-]+' | sort -u)

# Lo mismo para los usuarios de greetd, que es por donde entra la sesión en vivo.
while IFS= read -r usuario; do
    if existe_el_usuario "$usuario"; then
        ok "greetd user = ${usuario}"
    else
        mal "greetd user = ${usuario}: no existe ni en el passwd del perfil ni en un sysusers.d del ISO"
    fi
done < <(grep -oP '(?<=^user = ")[^"]+' airootfs/etc/greetd/config.toml 2>/dev/null | sort -u)

# ---------------------------------------------------------------------------
tema 'Los programas propios que nombran las unidades están y son ejecutables'

# Una unidad que apunta a `/usr/local/bin/algo` que no está en el árbol es una
# unidad que falla en el ISO y anda en el equipo de quien la escribió.
while IFS= read -r programa; do
    ruta="airootfs${programa}"
    if [ ! -f "$ruta" ]; then
        mal "${programa}: lo nombra una unidad y no está en el árbol"
    elif [ ! -x "$ruta" ]; then
        mal "${programa}: está pero no es ejecutable"
    elif ! grep -qF "\"${programa}\"" profiledef.sh; then
        # `mkarchiso` sólo avisa con un warning si falta, y el permiso del árbol
        # no sobrevive al empaquetado: sin la entrada en `file_permissions` el
        # programa llega al ISO sin el bit de ejecución.
        mal "${programa}: falta su entrada en file_permissions de profiledef.sh"
    else
        ok "${programa}"
    fi
done < <(grep -rhoP '(?<=^Exec)(?:Start|StartPre|StartPost|Condition|Stop)=-?\K/usr/local/bin/[^ ]+' \
    airootfs/etc/systemd/ 2>/dev/null | sort -u)

# ---------------------------------------------------------------------------
tema 'Los guiones propios no tienen errores de sintaxis'

while IFS= read -r guion; do
    if bash -n "$guion" 2>/dev/null; then
        ok "${guion#airootfs}"
    else
        mal "${guion#airootfs}: no pasa bash -n"
        bash -n "$guion"
    fi
done < <(find airootfs/usr/local/bin -type f 2>/dev/null | sort)

# ---------------------------------------------------------------------------
tema 'Las unidades propias las entiende systemd'

# Se copian a un directorio aparte porque `systemd-analyze verify` sigue las
# dependencias y, apuntado al árbol entero, arrastra medio sistema del equipo
# donde corre. Las quejas de «no existe el programa» son esperables: los
# programas viven en el ISO, no acá.
temporal=$(mktemp -d)
trap 'rm -rf "$temporal"' EXIT

for unidad in airootfs/etc/systemd/system/vasak-*.service airootfs/etc/systemd/system/vasak-*.timer; do
    [ -e "$unidad" ] || continue
    cp "$unidad" "$temporal/"
done

if [ -n "$(ls -A "$temporal" 2>/dev/null)" ]; then
    salida=$(systemd-analyze verify "$temporal"/* 2>&1 | grep -vE 'is not executable|Unit .* not found' || true)
    if [ -z "$salida" ]; then
        ok 'las unidades vasak-* parsean'
    else
        mal 'systemd-analyze tiene algo que decir:'
        printf '%s\n' "$salida"
    fi
fi

# ---------------------------------------------------------------------------
tema 'Hay una salida cuando el escritorio no abre'

# Las tres piezas del camino de la pantalla negra. Si falta una, el ISO vuelve
# a quedarse sin forma de contar qué pasó, que es de donde venimos.
[ -f airootfs/etc/systemd/system/greetd.service.d/sin-escritorio.conf ] \
    && grep -q 'OnFailure=vasak-sin-escritorio.service' airootfs/etc/systemd/system/greetd.service.d/sin-escritorio.conf \
    && ok 'greetd avisa cuando se rinde' \
    || mal 'greetd no tiene OnFailure=: si agota los reintentos no queda nada en pantalla'

[ -L airootfs/etc/systemd/system/timers.target.wants/vasak-sin-escritorio.timer ] \
    && ok 'el temporizador de los 90 s está habilitado' \
    || mal 'el temporizador no está habilitado: greetd puede quedar activo con la pantalla negra igual'

grep -q 'vasak-informe' airootfs/usr/local/bin/vasak-sin-escritorio 2>/dev/null \
    && ok 'el informe se escribe solo' \
    || mal 'no se escribe ningún informe, que es lo que faltaba en el reporte original'

# ---------------------------------------------------------------------------
printf '\n'
if [ "$fallos" -eq 0 ]; then
    printf '\033[32mTodo bien.\033[0m\n'
else
    printf '\033[31m%s comprobación(es) fallaron.\033[0m\n' "$fallos"
fi
exit "$((fallos > 0 ? 1 : 0))"
