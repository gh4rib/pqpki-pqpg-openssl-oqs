#!/usr/bin/env bash

# ==============================================================================
# POST-QUANTUM MODULE 2: SECURE MESSAGING & IDENTITY ENGINE (v8.0)
# Architecture: Hybrid KEM (X25519 + ML-KEM) + Encrypt-then-MAC + SPHINCS+ Identity
# Patch Notes: Added Fingerprinting, SLH-DSA, and Hybrid safety-net KEX.
# ==============================================================================
set -e
set -o pipefail

PROVIDER_ARGS=("-provider" "default" "-provider" "oqsprovider")

# --- EXHAUSTIVE ALGORITHM LISTS ---
# KEMs used for Ephemeral Session Keys
LIST_KEMS=(
    "MLKEM512" "MLKEM768" "MLKEM1024"
    "p256_mlkem512" "p384_mlkem768" "p521_mlkem1024" 
    "frodo640aes" "p256_frodo640aes" "frodo640shake" "p256_frodo640shake" 
    "frodo976aes" "p384_frodo976aes" "frodo976shake" "p384_frodo976shake" 
    "frodo1344aes" "p521_frodo1344aes" "frodo1344shake" "p521_frodo1344shake"
)

# Identity Signatures (Added SPHINCS+ / SLH-DSA for ultra-conservative security)
LIST_SIGS=(
    "MLDSA87" "MLDSA65" "MLDSA44" 
    "SLH-DSA-SHA2-128s" "SLH-DSA-SHA2-128f" "SLH-DSA-SHA2-256s" "SLH-DSA-SHA2-256f"
    "SLH-DSA-SHAKE-128s" "SLH-DSA-SHAKE-128f" "SLH-DSA-SHAKE-256s" "SLH-DSA-SHAKE-256f"
    "falcon1024" "falcon512" "p384_mldsa65" "p521_mldsa87"
)

LIST_CIPHERS=("aes-256-cbc" "aes-256-ctr" "chacha20" "camellia-256-cbc")

LIST_DIGESTS=(
    "SHA256" "SHA512" "SHA512-224" "SHA512-256"
    "SHA3-224" "SHA3-256" "SHA3-384" "SHA3-512"
    "SHAKE128" "SHAKE256"
    "KECCAK-224" "KECCAK-256" "KECCAK-384" "KECCAK-512"
    "BLAKE2s256" "BLAKE2b512"
    "SM3" "RIPEMD160" "SHA1" "MD5"
)

# --- HELPER ROUTINES ---
select_variant() {
    local -n list=$1
    for i in "${!list[@]}"; do
        echo "$((i+1))) ${list[$i]}" >&2
    done
    local choice
    while true; do
        read -p "Selection [1-${#list[@]}]: " choice >&2
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#list[@]}" ]; then
            echo "${list[$((choice-1))]}"
            return
        else
            echo "[!] Invalid input." >&2
        fi
    done
}

if ! command -v xxd &> /dev/null; then
    echo "[-] CRITICAL: 'xxd' is not installed. Please run: sudo apt install xxd"
    exit 1
fi

clear
echo "====================================================================="
echo "        POST-QUANTUM E2EE MESSAGING ENGINE (v8.0)"
echo "====================================================================="
echo "1) Generate New Identity Keyring (Keys to keep & share)"
echo "2) Generate Cryptographic Fingerprints (For GitHub/Bio)"
echo "3) Encrypt & Sign a Message (Send via Hybrid KEX)"
echo "4) Decrypt & Verify a Message (Receive)"
echo "====================================================================="
read -p "Select Action [1-4]: " action_choice

case "$action_choice" in
    1)
        # -----------------------------------------------------------------
        # IDENTITY GENERATION
        # -----------------------------------------------------------------
        echo -e "\n--- GENERATE NEW IDENTITY ---"
        read -p "Enter a username for this identity (e.g., alice): " username
        SAFE_USER=$(echo "$username" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')
        ID_DIR="./identity_${SAFE_USER}"
        
        mkdir -p "${ID_DIR}/private" "${ID_DIR}/public"
        
        echo -e "\n[1/3] Generating Classical X25519 Routing Key (For Hybrid Safety Net)..."
        openssl genpkey "${PROVIDER_ARGS[@]}" -algorithm X25519 -out "${ID_DIR}/private/x25519.priv"
        openssl pkey "${PROVIDER_ARGS[@]}" -in "${ID_DIR}/private/x25519.priv" -pubout -out "${ID_DIR}/public/x25519.pub"
        
        echo -e "\n[2/3] Select Post-Quantum KEM Mechanism (For Hybrid Safety Net):"
        KEM_ALG=$(select_variant LIST_KEMS)
        openssl genpkey "${PROVIDER_ARGS[@]}" -algorithm "$KEM_ALG" -out "${ID_DIR}/private/pq_kem.priv"
        openssl pkey "${PROVIDER_ARGS[@]}" -in "${ID_DIR}/private/pq_kem.priv" -pubout -out "${ID_DIR}/public/pq_kem.pub"
        
        echo -e "\n[3/3] Select Identity Signature Algorithm (Recommend SLH-DSA for long-term):"
        SIG_ALG=$(select_variant LIST_SIGS)
        openssl genpkey "${PROVIDER_ARGS[@]}" -algorithm "$SIG_ALG" -out "${ID_DIR}/private/sig.priv"
        openssl pkey "${PROVIDER_ARGS[@]}" -in "${ID_DIR}/private/sig.priv" -pubout -out "${ID_DIR}/public/sig.pub"
        
        echo -e "\n\e[32m[+] Identity Created Successfully!\e[0m"
        echo "Private Keystore: ${ID_DIR}/private/ (Keep this secure!)"
        echo "Public Keystore:  ${ID_DIR}/public/  (Send this folder to your contacts)"
        ;;

    2)
        # -----------------------------------------------------------------
        # FINGERPRINT GENERATION
        # -----------------------------------------------------------------
        echo -e "\n--- GENERATE CRYPTOGRAPHIC FINGERPRINTS ---"
        read -e -p "Path to your Public Keyring folder (e.g., ./identity_alice/public): " PUB_DIR
        
        if [ ! -d "$PUB_DIR" ]; then echo "[-] Folder not found."; exit 1; fi
        
        echo -e "\n\e[36mCopy these short fingerprints to your GitHub, Twitter, or Website:\e[0m"
        echo "------------------------------------------------------------------"
        if [ -f "${PUB_DIR}/sig.pub" ]; then
            FINGERPRINT=$(openssl dgst "${PROVIDER_ARGS[@]}" -sha256 -c "${PUB_DIR}/sig.pub" | awk -F'= ' '{print $2}')
            echo "[IDENTITY] Signature Key:  $FINGERPRINT"
        fi
        if [ -f "${PUB_DIR}/pq_kem.pub" ]; then
            FINGERPRINT=$(openssl dgst "${PROVIDER_ARGS[@]}" -sha256 -c "${PUB_DIR}/pq_kem.pub" | awk -F'= ' '{print $2}')
            echo "[ROUTING]  Post-Quantum:   $FINGERPRINT"
        fi
        if [ -f "${PUB_DIR}/x25519.pub" ]; then
            FINGERPRINT=$(openssl dgst "${PROVIDER_ARGS[@]}" -sha256 -c "${PUB_DIR}/x25519.pub" | awk -F'= ' '{print $2}')
            echo "[ROUTING]  Classical Curve: $FINGERPRINT"
        fi
        echo "------------------------------------------------------------------"
        ;;
        
    3)
        # -----------------------------------------------------------------
        # ENCRYPT AND SIGN (HYBRID KEX)
        # -----------------------------------------------------------------
        echo -e "\n--- ENCRYPT & SIGN MESSAGE ---"
        read -e -p "Path to YOUR Private Keyring folder (e.g., ./identity_alice/private): " MY_PRIV_DIR
        read -e -p "Path to RECIPIENT'S Public Keyring folder (e.g., ./identity_bob/public): " REC_PUB_DIR
        read -e -p "Path to the raw message file to send: " MSG_FILE
        
        if [ ! -f "$MSG_FILE" ]; then echo "[-] Message file not found."; exit 1; fi

        echo -e "\nSelect Symmetric Payload Cipher:"
        CIPHER=$(select_variant LIST_CIPHERS)
        
        echo -e "\nSelect Digest Hash for Identity Signature:"
        HASH_ALG=$(select_variant LIST_DIGESTS)
        
        TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
        OUT_DIR="./outbox_msg_${TIMESTAMP}"
        mkdir -p "$OUT_DIR"
        
        echo "[*] 1/7 Encapsulating Classical X25519 Secret..."
        openssl pkeyutl "${PROVIDER_ARGS[@]}" -derive -inkey "${MY_PRIV_DIR}/x25519.priv" -peerkey "${REC_PUB_DIR}/x25519.pub" -out "${OUT_DIR}/classic_secret.bin"
        
        echo "[*] 2/7 Encapsulating Post-Quantum KEM Secret..."
        openssl pkeyutl "${PROVIDER_ARGS[@]}" -encap -pubin -inkey "${REC_PUB_DIR}/pq_kem.pub" -out "${OUT_DIR}/pq_payload.encap" -secret "${OUT_DIR}/pq_secret.bin"
        
        echo "[*] 3/7 Deriving Hybrid Cipher Key and MAC Key..."
        # We concatenate both the classical and PQ secrets, then hash them together to create a true Hybrid Key
        cat "${OUT_DIR}/classic_secret.bin" "${OUT_DIR}/pq_secret.bin" | openssl dgst -sha512 -binary > "${OUT_DIR}/master_secret.bin"
        HEX_KEY=$(xxd -p -c 64 "${OUT_DIR}/master_secret.bin" | cut -c 1-64) # First 32 bytes for AES
        MAC_KEY=$(xxd -p -c 64 "${OUT_DIR}/master_secret.bin" | cut -c 65-128) # Second 32 bytes for HMAC
        
        HEX_IV=$(openssl rand -hex 16)
        echo "$HEX_IV" > "${OUT_DIR}/payload.iv"
        
        # We MUST send our public X25519 key so the recipient can derive the classical half of the secret
        cp "${MY_PRIV_DIR}/../public/x25519.pub" "${OUT_DIR}/sender_x25519.pub"
        
        echo "[*] 4/7 Encrypting payload with ${CIPHER}..."
        openssl enc -"${CIPHER}" -K "$HEX_KEY" -iv "$HEX_IV" -in "$MSG_FILE" -out "${OUT_DIR}/payload.cipher"
        
        echo "[*] 5/7 Generating AEAD Authentication Tag (HMAC)..."
        openssl dgst -sha256 -mac HMAC -macopt hexkey:"$MAC_KEY" -binary -out "${OUT_DIR}/payload.tag" "${OUT_DIR}/payload.cipher"
        
        echo "[*] 6/7 Hashing and Signing cryptographic bundle with PQ Identity..."
        # We must sign the sender's ephemeral classical key too, to prevent Man-in-the-Middle attacks on the hybrid mix
        cat "${OUT_DIR}/payload.cipher" "${OUT_DIR}/payload.iv" "${OUT_DIR}/payload.tag" "${OUT_DIR}/sender_x25519.pub" > "${OUT_DIR}/temp.bundle"
        
        if [[ "$HASH_ALG" == *"SHAKE"* ]]; then
            openssl dgst "${PROVIDER_ARGS[@]}" -"$HASH_ALG" -xoflen 64 -binary -out "${OUT_DIR}/payload.hash" "${OUT_DIR}/temp.bundle"
        else
            openssl dgst "${PROVIDER_ARGS[@]}" -"$HASH_ALG" -binary -out "${OUT_DIR}/payload.hash" "${OUT_DIR}/temp.bundle"
        fi
        
        openssl pkeyutl "${PROVIDER_ARGS[@]}" -sign -rawin -in "${OUT_DIR}/payload.hash" -inkey "${MY_PRIV_DIR}/sig.priv" -out "${OUT_DIR}/payload.sig"
        
        echo "[*] 7/7 Scrubbing memory..."
        rm -f "${OUT_DIR}/classic_secret.bin" "${OUT_DIR}/pq_secret.bin" "${OUT_DIR}/master_secret.bin" "${OUT_DIR}/temp.bundle" "${OUT_DIR}/payload.hash"
        
        echo -e "\n\e[32m[+] Message Encrypted and Signed Successfully!\e[0m"
        echo "Send the entire folder to the recipient: $OUT_DIR"
        ;;
        
    4)
        # -----------------------------------------------------------------
        # DECRYPT AND VERIFY (HYBRID KEX)
        # -----------------------------------------------------------------
        echo -e "\n--- DECRYPT & VERIFY MESSAGE ---"
        read -e -p "Path to YOUR Private Keyring folder (e.g., ./identity_bob/private): " MY_PRIV_DIR
        read -e -p "Path to SENDER'S Public Keyring folder (e.g., ./identity_alice/public): " SENDER_PUB_DIR
        read -e -p "Path to the received message folder (e.g., ./outbox_msg_2026...): " MSG_DIR
        
        if [ ! -d "$MSG_DIR" ]; then echo "[-] Message folder not found."; exit 1; fi
        
        echo -e "\nSelect Symmetric Payload Cipher used by sender:"
        CIPHER=$(select_variant LIST_CIPHERS)
        
        echo -e "\nSelect Digest Hash used by sender:"
        HASH_ALG=$(select_variant LIST_DIGESTS)

        echo "[*] 1/6 Verifying Post-Quantum Cryptographic Identity Signature..."
        cat "${MSG_DIR}/payload.cipher" "${MSG_DIR}/payload.iv" "${MSG_DIR}/payload.tag" "${MSG_DIR}/sender_x25519.pub" > "${MSG_DIR}/temp.bundle"
        
        if [[ "$HASH_ALG" == *"SHAKE"* ]]; then
            openssl dgst "${PROVIDER_ARGS[@]}" -"$HASH_ALG" -xoflen 64 -binary -out "${MSG_DIR}/payload.hash" "${MSG_DIR}/temp.bundle"
        else
            openssl dgst "${PROVIDER_ARGS[@]}" -"$HASH_ALG" -binary -out "${MSG_DIR}/payload.hash" "${MSG_DIR}/temp.bundle"
        fi
        
        if openssl pkeyutl "${PROVIDER_ARGS[@]}" -verify -rawin -in "${MSG_DIR}/payload.hash" -sigfile "${MSG_DIR}/payload.sig" -pubin -inkey "${SENDER_PUB_DIR}/sig.pub"; then
            echo -e "\e[32m    -> IDENTITY VALID: Sender confirmed.\e[0m"
        else
            echo -e "\e[31m[-] CRITICAL: Signature Verification Failed! Message was tampered with or sender is spoofed.\e[0m"
            rm -f "${MSG_DIR}/temp.bundle" "${MSG_DIR}/payload.hash"
            exit 1
        fi
        
        echo "[*] 2/6 Decapsulating Classical X25519 Secret..."
        openssl pkeyutl "${PROVIDER_ARGS[@]}" -derive -inkey "${MY_PRIV_DIR}/x25519.priv" -peerkey "${MSG_DIR}/sender_x25519.pub" -out "${MSG_DIR}/classic_secret.bin"
        
        echo "[*] 3/6 Decapsulating Post-Quantum KEM Secret..."
        openssl pkeyutl "${PROVIDER_ARGS[@]}" -decap -inkey "${MY_PRIV_DIR}/pq_kem.priv" -in "${MSG_DIR}/pq_payload.encap" -out "${MSG_DIR}/pq_secret.bin"
        
        echo "[*] 4/6 Verifying Authentication Tag (HMAC AEAD Check)..."
        cat "${MSG_DIR}/classic_secret.bin" "${MSG_DIR}/pq_secret.bin" | openssl dgst -sha512 -binary > "${MSG_DIR}/master_secret.bin"
        HEX_KEY=$(xxd -p -c 64 "${MSG_DIR}/master_secret.bin" | cut -c 1-64) 
        MAC_KEY=$(xxd -p -c 64 "${MSG_DIR}/master_secret.bin" | cut -c 65-128) 
        HEX_IV=$(cat "${MSG_DIR}/payload.iv")
        
        openssl dgst -sha256 -mac HMAC -macopt hexkey:"$MAC_KEY" -binary -out "${MSG_DIR}/calculated.tag" "${MSG_DIR}/payload.cipher"
        
        if cmp -s "${MSG_DIR}/payload.tag" "${MSG_DIR}/calculated.tag"; then
            echo -e "\e[32m    -> AEAD INTEGRITY VALID: Ciphertext has not been tampered with.\e[0m"
        else
            echo -e "\e[31m[-] CRITICAL: Authentication Tag Mismatch! Ciphertext is corrupt.\e[0m"
            rm -f "${MSG_DIR}/classic_secret.bin" "${MSG_DIR}/pq_secret.bin" "${MSG_DIR}/master_secret.bin" "${MSG_DIR}/temp.bundle" "${MSG_DIR}/payload.hash" "${MSG_DIR}/calculated.tag"
            exit 1
        fi
        
        echo "[*] 5/6 Decrypting Payload (${CIPHER})..."
        openssl enc -d -"${CIPHER}" -K "$HEX_KEY" -iv "$HEX_IV" -in "${MSG_DIR}/payload.cipher" -out "${MSG_DIR}/decrypted_message.txt"
        
        echo "[*] 6/6 Scrubbing memory..."
        rm -f "${MSG_DIR}/classic_secret.bin" "${MSG_DIR}/pq_secret.bin" "${MSG_DIR}/master_secret.bin" "${MSG_DIR}/temp.bundle" "${MSG_DIR}/payload.hash" "${MSG_DIR}/calculated.tag"
        
        echo -e "\n\e[32m[+] Message Decrypted Successfully!\e[0m"
        echo "Payload extracted to: ${MSG_DIR}/decrypted_message.txt"
        ;;
        
    *)
        echo "[-] Invalid Selection."
        exit 1
        ;;
esac
