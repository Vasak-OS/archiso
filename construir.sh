#!/usr/bin/env bash
#
# construir.sh — armar la ISO de VasakOS sin dejar el sistema sucio.
#
# Es un envoltorio finito alrededor de `mkarchiso`. No cambia cómo se arma la
# imagen: se ocupa de las dos formas en que armarla a mano salió mal.
#
# # 1. Nunca `-r`
#
# `mkarchiso -r` borra el directorio de trabajo cuando termina, y en el camino
# hace `rm -rf` sobre `airootfs`. El problema es que ahí adentro está montado el
# `/sys` del sistema **anfitrión**, y colgando de él `efivarfs`, que es de
# lectura y escritura: ese `rm` no le entra a la imagen, le entra a las
# variables UEFI de la placa, entradas de arranque incluidas.
#
# Pasó de verdad. La imagen se armó igual y la limpieza final escupió cientos de
# «cannot remove ... Read-only file system» — que es lo que frena al `rm` en el
# `/sys`, pero el `/sys` es de sólo lectura por casualidad, no por diseño de
# nadie: lo que cuelga abajo sí se escribe.
#
# Así que acá el directorio de trabajo se borra **después**, y sólo cuando se
# comprobó que no queda nada montado.
#
# # 2. Nunca sobre un árbol con montajes colgados
#
# Si una construcción anterior quedó a mitad de camino, esos montajes siguen
# vivos. Arrancar de nuevo encima es cómo se llega al caso de arriba, así que
# esto se niega a empezar y dice qué desmontar.
#
# # Uso
#
#   sudo ./construir.sh [directorio-de-salida]
#
# El directorio de trabajo va en el `$HOME` de quien invoca y no en `/tmp`: en
# muchas instalaciones `/tmp` es un tmpfs —o sea RAM— y acá se descomprime un
# árbol de 6-8 GB y se escribe el squashfs al lado. El pico ronda los 15 GB.

set -euo pipefail

PERFIL="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# El $HOME de la persona, no el de root: `sudo` cambia el usuario efectivo pero
# la imagen y el árbol de trabajo son de quien está trabajando.
CASA="${SUDO_USER:+/home/$SUDO_USER}"
CASA="${CASA:-$HOME}"

TRABAJO="$CASA/archiso-work"
SALIDA="${1:-$CASA/isos}"

rojo=$'\033[0;31m'; verde=$'\033[0;32m'; amarillo=$'\033[0;33m'; sin=$'\033[0m'
[[ -t 1 ]] || { rojo=""; verde=""; amarillo=""; sin=""; }

# Lo que quedó montado bajo el árbol de trabajo, si algo quedó.
#
# Se lee `/proc/mounts` y no `findmnt`, porque `findmnt` no lista un montaje
# cuyo punto de montaje ya no existe como ruta accesible — y ése es justamente
# el caso que interesa.
montajes() {
  awk -v dir="$TRABAJO" '$2 ~ "^" dir { print $2 }' /proc/mounts | sort -r
}

if [[ $EUID -ne 0 ]]; then
  echo "${rojo}Hace falta root:${sin} mkarchiso monta y hace chroot." >&2
  echo "  sudo $0 $*" >&2
  exit 1
fi

# ── Antes de empezar ────────────────────────────────────────────────────────

pendientes="$(montajes)"
if [[ -n $pendientes ]]; then
  echo "${rojo}Hay montajes colgados de una construcción anterior:${sin}" >&2
  echo "$pendientes" | sed 's/^/  /' >&2
  echo >&2
  echo "Desmontá y borrá el árbol antes de seguir. En ese orden, y comprobando:" >&2
  echo "  umount -R $TRABAJO/x86_64/airootfs" >&2
  echo "  grep archiso-work /proc/mounts   # tiene que no devolver nada" >&2
  echo "  rm -rf $TRABAJO" >&2
  echo >&2
  echo "${amarillo}No borres el árbol sin desmontar:${sin} ahí adentro está montado el" >&2
  echo "/sys de esta máquina, y abajo efivarfs, que sí se puede escribir." >&2
  exit 1
fi

if [[ -e $TRABAJO ]]; then
  echo "${amarillo}El árbol de trabajo ya existe y no tiene montajes:${sin} $TRABAJO"
  echo "Se borra para empezar limpio."
  rm -rf -- "$TRABAJO"
fi

install -d -- "$SALIDA"

# ── La construcción ─────────────────────────────────────────────────────────

echo "${verde}Armando la ISO${sin}"
echo "  perfil:   $PERFIL"
echo "  trabajo:  $TRABAJO"
echo "  salida:   $SALIDA"
echo

# Sin `-r`, a propósito y para siempre. Ver el encabezado.
estado=0
mkarchiso -v -w "$TRABAJO" -o "$SALIDA" "$PERFIL" || estado=$?

# ── Después, pase lo que pase ───────────────────────────────────────────────
#
# La limpieza corre también cuando la construcción falló: es justamente el caso
# que deja montajes colgados, y dejarlos es lo que arruina el intento siguiente.

pendientes="$(montajes)"
if [[ -n $pendientes ]]; then
  echo
  echo "${amarillo}Quedaron montajes; desmontando antes de borrar:${sin}"
  echo "$pendientes" | sed 's/^/  /'
  # De más profundo a menos —`montajes` ordena al revés— porque un punto de
  # montaje con algo montado abajo está ocupado y no se desmonta.
  while read -r punto; do
    [[ -n $punto ]] || continue
    umount -R -- "$punto" 2>/dev/null || umount -l -- "$punto" 2>/dev/null || true
  done <<< "$pendientes"
fi

# Se vuelve a mirar: si algo sigue montado, el árbol **no se borra**. Es la única
# regla que no se negocia acá, porque borrar con algo montado es cómo se le entra
# a las variables UEFI de la placa.
pendientes="$(montajes)"
if [[ -n $pendientes ]]; then
  echo
  echo "${rojo}No se pudo desmontar todo, así que no se borra nada:${sin}" >&2
  echo "$pendientes" | sed 's/^/  /' >&2
  echo "Revisá qué lo tiene ocupado (lsof, fuser) y desmontá a mano." >&2
  exit 1
fi

if [[ -d $TRABAJO ]]; then
  rm -rf -- "$TRABAJO"
fi

if [[ $estado -ne 0 ]]; then
  echo
  echo "${rojo}mkarchiso falló (código $estado).${sin} El árbol se limpió igual." >&2
  exit "$estado"
fi

echo
echo "${verde}Listo.${sin} La imagen quedó en $SALIDA:"
ls -lh -- "$SALIDA"/*.iso 2>/dev/null | tail -3
