#!/bin/bash

get_vault_secret() {
    local key=$1
    local value=$(curl --silent --header "X-Vault-Token: ${VAULT_TOKEN}" \
                  "${VAULT_URL}/v1/secret/data/devsecops" | jq -r ".data.data.${key}")
    
    if [[ "$value" == "null" || -z "$value" ]]; then
        echo ""
    else
        echo "$value"
    fi
}


push_vault_secret() {
    local key=$1
    local value=$2
    

    existing_data=$(curl --silent --header "X-Vault-Token: ${VAULT_TOKEN}" \
                   "${VAULT_URL}/v1/secret/data/devsecops" | jq -r ".data.data")
    
    updated_data=$(echo "$existing_data" | jq --arg k "$key" --arg v "$value" '.[$k] = $v')
    
    curl --silent --request POST --header "X-Vault-Token: ${VAULT_TOKEN}" \
         --data "{\"data\": $updated_data}" \
         "${VAULT_URL}/v1/secret/data/devsecops" > /dev/null
    
    echo "Pushed $key to Vault."
}


