#!/usr/bin/env bash
set -euo pipefail

# ======= Config =======
REGION="us-east-1"
TENANT="acme"
TEXTO="hola desde curl"

URL_DEV="https://s7jkiu9qy1.execute-api.us-east-1.amazonaws.com/dev/comentario/crear"
URL_TEST="https://w36zl2y197.execute-api.us-east-1.amazonaws.com/test/comentario/crear"
URL_PROD="https://zoileue4sh.execute-api.us-east-1.amazonaws.com/prod/comentario/crear"

# Si usas un perfil específico, descomenta:
# export AWS_PROFILE=default

parse_uuid () {
python3 -c '
import sys, json, re
raw = sys.stdin.read()

# Intento robusto con doble parseo si hay "body"
try:
    outer = json.loads(raw)
    if isinstance(outer, dict) and "body" in outer:
        body = outer["body"]
        try:
            if isinstance(body, str):
                inner = json.loads(body)
            else:
                inner = body
            print(inner["comentario"]["uuid"])
            sys.exit(0)
        except Exception:
            pass
    # Intento directo (por si algún día no hay "body")
    if isinstance(outer, dict) and "comentario" in outer:
        print(outer["comentario"]["uuid"])
        sys.exit(0)
except Exception:
    pass

# Fallback por regex (por si todo lo demás falla)
m = re.search(r"\"uuid\"\s*:\s*\"([^\"]+)\"", raw)
print(m.group(1) if m else "")
'
}

call_and_verify () {
  local STAGE="$1"
  local URL="$2"

  echo -e "\n================= TEST $STAGE ================="
  echo "POST $URL"
  RESP=$(curl -s -X POST "$URL" -H "Content-Type: application/json" \
    -d "{\"tenant_id\":\"$TENANT\",\"texto\":\"$TEXTO\"}")

  echo "Respuesta cruda:"
  echo "$RESP"

  UUID=$(echo "$RESP" | parse_uuid)

  if [[ -z "$UUID" ]]; then
    echo "No pude extraer el UUID. Revisa la respuesta ↑"
    exit 1
  fi
  echo "UUID: $UUID"

  ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --region "$REGION")
  BUCKET="api-comentario-$STAGE-$ACCOUNT_ID-ingesta"
  KEY="$STAGE/$TENANT/$UUID.json"
  TABLE="${STAGE}-t_comentarios"

  echo "Bucket: $BUCKET"
  echo "Clave S3: $KEY"
  echo "Tabla DDB: $TABLE"

  echo "- Listando objetos en s3://$BUCKET/$STAGE/$TENANT/"
  aws s3 ls "s3://$BUCKET/$STAGE/$TENANT/" --region "$REGION" --recursive | tail -n 5 || true

  echo "- Descargando y mostrando el JSON recién subido"
  aws s3 cp "s3://$BUCKET/$KEY" - --region "$REGION" | python3 -m json.tool

  echo "- Consultando en DynamoDB por tenant_id+uuid"
  aws dynamodb get-item \
    --region "$REGION" \
    --table-name "$TABLE" \
    --key "{\"tenant_id\":{\"S\":\"$TENANT\"},\"uuid\":{\"S\":\"$UUID\"}}"
}

call_and_verify "dev"  "$URL_DEV"
call_and_verify "test" "$URL_TEST"
call_and_verify "prod" "$URL_PROD"

echo -e "\nListo. Verificado en los tres stages."