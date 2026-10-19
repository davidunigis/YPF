#!/usr/bin/env bash
# Requests a la API gis-utilities (CAS Optimax) segun "GIS - CAS Optimax" v3 (24/07/2026).
# Uso:
#   export YGEO_API_KEY='<api key del entorno>'     # no commitear la key
#   ./ygeo-requests.sh [des|tst] ultima-posicion PATENTE [PATENTE...]
#   ./ygeo-requests.sh [des|tst] eta convencional|emergencia LAT,LON LAT,LON [LAT,LON ...]   (2 a 5 puntos)
# Entorno por defecto: des. DRY_RUN=1 muestra el request sin enviarlo.
# Requiere curl y jq; los hosts son internos de YPF (red/VPN).
set -euo pipefail

usage() { sed -n '2,8p' "$0" >&2; exit 1; }

env_name=des
case "${1:-}" in
  des|tst) env_name=$1; shift ;;
esac

: "${YGEO_API_KEY:?Definir YGEO_API_KEY con la API key del entorno}"
base_url="https://gis-utilities-api-${env_name}.grupo.ypf.com"

call() { # $1 = endpoint, $2 = body JSON
  local url="$base_url/v1/Ruteo/$1" out rc=0
  if [[ -n "${DRY_RUN:-}" ]]; then
    printf 'POST %s\nContent-Type: application/json\nygeo-api-key: ***\n\n%s\n' "$url" "$(jq . <<<"$2")"
    return
  fi
  out=$(curl -sS --fail-with-body -X POST "$url" \
    -H 'Content-Type: application/json' \
    -H "ygeo-api-key: $YGEO_API_KEY" \
    -d "$2") || rc=$?
  jq . <<<"$out" 2>/dev/null || printf '%s\n' "$out"
  return "$rc"
}

cmd=${1:-}
[[ -n "$cmd" ]] && shift
case "$cmd" in
  ultima-posicion)
    (( $# >= 1 )) || { echo "Se requiere al menos 1 patente" >&2; exit 1; }
    call UltimaPosicion "$(jq -n '{patentes: $ARGS.positional}' --args "$@")"
    ;;
  eta)
    tipo=${1:-}
    [[ -n "$tipo" ]] && shift
    [[ "$tipo" == convencional || "$tipo" == emergencia ]] || { echo "tipo_ruteo debe ser convencional o emergencia" >&2; exit 1; }
    (( $# >= 2 && $# <= 5 )) || { echo "Se requieren entre 2 y 5 puntos LAT,LON" >&2; exit 1; }
    call ObtenerEta "$(jq -n --arg t "$tipo" '{
      tipo_ruteo: $t,
      stops: ($ARGS.positional | map(split(",") | {latitud: (.[0] | tonumber), longitud: (.[1] | tonumber)}))
    }' --args "$@")"
    ;;
  *) usage ;;
esac
