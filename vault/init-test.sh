#!/bin/bash

# vim: filetype=sh:tabstop=2:shiftwidth=2:expandtab

# https://www.vaultproject.io/docs/http/ 

if [ -z "$1" ]; then
  echo "This script requires the name of your deployed Vault service (e.g. \"dev-vault\")"
  exit 1
fi

temp_ip=$(kubectl get svc $1 -o json | jq .status.loadBalancer.ingress[0].ip)
temp_ip="${temp_ip%\"}"
readonly SVC_IP="${temp_ip#\"}"

if [ -z "$SVC_IP" ]; then
  echo "Unable to determine external ip address for service \"$1\""
  exit 1
fi

readonly TEST_TRUE="true"
readonly TEST_FALSE="true"

## some misc. messaging functions
warn() {
  echo -e "\033[1;33mWARNING: $1\033[0m"
}

error() {
  echo -e "\033[0;31mERROR: $1\033[0m"
}

inf() {
  echo -e "\033[0;32m$1\033[0m"
}

test_https_status() {
  inf ""
  inf "First, see if tls handshake works" 
  curl \
    -k \
    -s \
    -X GET \
    "https://$SVC_IP:8200/v1/sys/init"
  
  inf "...apparently this vault instance is configured with tls" 
}

## now, for some real work
system_status() {
  curl \
    -k \
    -s \
    -X GET \
    "https://$SVC_IP:8200/v1/sys/init" | jq .initialized
}

system_initialized() {
  local fstatus=$(system_status)
  local rtn=1
  
  if [ "$fstatus" == "true" ]; then
    rtn=0
  fi
  return $rtn
}

init_system() {
  echo ""
  inf "Initialize vault..."
  echo ""

  local init_out=$(curl \
    -k \
    -s \
    -X PUT \
    -d "{\"secret_shares\":1, \"secret_threshold\":1}" \
    "https://$SVC_IP:8200/v1/sys/init")

  local temp_unseal_key=$(echo $init_out | jq .keys[0])
  temp_unseal_key="${temp_unseal_key%\"}"
  readonly TEST_UNSEAL_KEY="${temp_unseal_key#\"}"
  inf "  Unseal Key: $TEST_UNSEAL_KEY"

  local temp_root_token=$(echo $init_out | jq .root_token)
  temp_root_token="${temp_root_token%\"}"
  readonly TEST_VAULT_TOKEN="${temp_root_token#\"}"
  inf "  Root Token: $TEST_VAULT_TOKEN"

  inf ""
  inf ""
  inf "  Attempting to unseal vault instance..."

  local unseal_out=$(curl \
    -k \
    -s \
    -X PUT \
    -d '{"key": "'"$TEST_UNSEAL_KEY"'"}' \
    "https://$SVC_IP:8200/v1/sys/unseal")

  local sealed_status=$(echo $unseal_out | jq .sealed)
  local rtn=1
  
  if [ "$sealed_status" == "false" ]; then
    rtn=0
    inf "    Vault instance is now unsealed"
  else
    error "    Failed to unseal vault instance"
    exit 1
  fi

  return $rtn
}


create_secret_baz() {
  echo ""
  inf "Create a test secret called \"baz\"..."
  echo ""

  curl \
    -k \
    -s \
    -H "X-Vault-Token: $TEST_VAULT_TOKEN" \
    -H "Content-Type: application/json" \
    -X POST \
    -d '{"value":"bar"}' \
    "https://$SVC_IP:8200/v1/secret/baz"
}


list_secrets() {
  echo ""
  inf "Listing secrets..."
  echo ""

  curl \
    -k \
    -s \
    -H "X-Vault-Token: $TEST_VAULT_TOKEN" \
    -X GET \
    "https://$SVC_IP:8200/v1/secret?list=true"
}


get_secret_baz() {
  echo ""
  inf "Retrieve a test secret called \"baz\"..."
  echo ""
  curl \
    -k \
    -s \
    -H "X-Vault-Token: $TEST_VAULT_TOKEN" \
    -X GET \
    "https://$SVC_IP:8200/v1/secret/baz"
}


main() {
  # Be unforgiving about errors
  set -euo pipefail

  # since this script is only set to test a TLS-based instance, attempt to check for https first. 
  test_https_status
   
  if system_initialized; then
    inf "The vault instance is already initialized."
  else 
    inf "The vault instance is not initialized."
    init_system
    create_secret_baz
    list_secrets
    get_secret_baz
  fi
}


[[ "$0" == "$BASH_SOURCE" ]] && main
