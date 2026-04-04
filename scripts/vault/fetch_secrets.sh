#!/bin/bash

get_vault_secret() {
    local key=$1
    # Use the variables already exported in the environment
    local value=$(curl --silent --header "X-Vault-Token: ${VAULT_TOKEN}" \
                  "${VAULT_URL}/v1/secret/data/devsecops" | jq -r ".data.data.${key}")
    
    if [[ "$value" == "null" || -z "$value" ]]; then
        echo ""
    else
        echo "$value"
    fi
}

# ... existing get_vault_secret function ...

push_vault_secret() {
    local key=$1
    local value=$2
    
    # This uses a PATCH-like approach to add a new key to the existing 'devsecops' secret
    # We fetch existing data first to avoid overwriting everything else
    existing_data=$(curl --silent --header "X-Vault-Token: ${VAULT_TOKEN}" \
                   "${VAULT_URL}/v1/secret/data/devsecops" | jq -r ".data.data")
    
    # Add the new key/value to the JSON
    updated_data=$(echo "$existing_data" | jq --arg k "$key" --arg v "$value" '.[$k] = $v')
    
    # Push it back to Vault
    curl --silent --request POST --header "X-Vault-Token: ${VAULT_TOKEN}" \
         --data "{\"data\": $updated_data}" \
         "${VAULT_URL}/v1/secret/data/devsecops" > /dev/null
    
    echo "📤 Pushed $key to Vault."
}
