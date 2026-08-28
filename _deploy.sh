#!/usr/bin/env bash
set -u
CLIENT_ID=178c6fc778ccc68e1d6a
REPO_NAME="ideaverse-web"
# Native Windows path (MSYS translation is disabled for native git in this env)
FOLDER="C:/Users/Computer Care/IdeaverseWeb"
API=https://api.github.com
TOKEN_FILE="$FOLDER/.deploy_token"

if [ -s "$TOKEN_FILE" ]; then
  TOKEN=$(cat "$TOKEN_FILE")
  LOGIN=$(curl -s -H "Authorization: token $TOKEN" $API/user | sed -n 's/.*"login": *"\([^"]*\)".*/\1/p')
  echo "REUSE_TOKEN LOGIN=$LOGIN"
else
  RESP=$(curl -s -X POST -H "Accept: application/json" \
    -d "client_id=$CLIENT_ID&scope=repo,read:org,gist" \
    https://github.com/login/device/code)
  DEVICE_CODE=$(echo "$RESP" | sed 's/.*"device_code":"\([^"]*\)".*/\1/')
  USER_CODE=$(echo "$RESP" | sed 's/.*"user_code":"\([^"]*\)".*/\1/')
  INTERVAL=$(echo "$RESP" | sed 's/.*"interval":\([0-9]*\).*/\1/'); INTERVAL=${INTERVAL:-5}
  echo "USER_CODE=$USER_CODE"
  echo ">>> Go to https://github.com/login/device and enter this code: $USER_CODE"
  while true; do
    sleep "$INTERVAL"
    POLL=$(curl -s -X POST -H "Accept: application/json" \
      -d "client_id=$CLIENT_ID&device_code=${DEVICE_CODE}&grant_type=urn:ietf:params:oauth:grant-type:device_code" \
      https://github.com/login/oauth/access_token)
    case "$POLL" in
      *access_token*) TOKEN=$(echo "$POLL" | sed 's/.*"access_token":"\([^"]*\)".*/\1/'); echo "AUTH_OK"; break ;;
      *authorization_pending*) ;;
      *slow_down*) INTERVAL=$((INTERVAL + 5)) ;;
      *expired_token*) echo "CODE_EXPIRED"; exit 1 ;;
      *access_denied*) echo "USER_DENIED"; exit 1 ;;
      *) echo "UNEXPECTED: $POLL"; exit 1 ;;
    esac
  done
  LOGIN=$(curl -s -H "Authorization: token $TOKEN" $API/user | sed -n 's/.*"login": *"\([^"]*\)".*/\1/p')
  echo "$TOKEN" > "$TOKEN_FILE"
  echo "LOGIN=$LOGIN"
  [ -z "$LOGIN" ] && { echo "FAILED to get login"; exit 1; }
fi

# create repo only if it doesn't already exist
HTTP=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: token $TOKEN" $API/repos/$LOGIN/$REPO_NAME)
if [ "$HTTP" = "404" ]; then
  curl -s -o /dev/null -w "create_status=%{http_code}\n" -X POST \
    -H "Authorization: token $TOKEN" -H "Accept: application/vnd.github+json" \
    -d "{\"name\":\"$REPO_NAME\",\"private\":false,\"auto_init\":false,\"description\":\"Ideaverse Web - read your Obsidian vault from anywhere\"}" \
    $API/user/repos
else
  echo "repo already exists (http=$HTTP), skipping creation"
fi

git -C "$FOLDER" init -q 2>/dev/null || true
git -C "$FOLDER" config user.name "$LOGIN"
git -C "$FOLDER" config user.email "$LOGIN@users.noreply.github.com"
git -C "$FOLDER" config credential.helper store
git -C "$FOLDER" remote remove origin 2>/dev/null || true
git -C "$FOLDER" remote add origin "https://$TOKEN@github.com/$LOGIN/$REPO_NAME.git"
git -C "$FOLDER" add index.html
git -C "$FOLDER" commit -q -m "Initial commit: Ideaverse Web reader" 2>/dev/null \
  || git -C "$FOLDER" commit -q -m "Initial commit"
git -C "$FOLDER" branch -M main
git -C "$FOLDER" push -q -u origin main && echo "PUSHED" || { echo "PUSH_FAILED"; exit 1; }
git -C "$FOLDER" remote set-url origin "https://github.com/$LOGIN/$REPO_NAME.git"

# enable Pages
curl -s -o /dev/null -w "pages_status=%{http_code}\n" -X POST \
  -H "Authorization: token $TOKEN" -H "Accept: application/vnd.github+json" \
  -d '{"source":{"branch":"main","path":"/"}}' \
  $API/repos/$LOGIN/$REPO_NAME/pages

# check Pages status (takes a moment to provision)
sleep 3
PAGES_URL=$(curl -s -H "Authorization: token $TOKEN" $API/repos/$LOGIN/$REPO_NAME/pages | sed -n 's/.*"html_url": *"\([^"]*\)".*/\1/p')
echo "PAGES_URL=$PAGES_URL"
echo "DEPLOY_DONE"
echo "URL=https://$LOGIN.github.io/$REPO_NAME/"
