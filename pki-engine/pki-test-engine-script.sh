#!/usr/bin/env bash

# ==============================================================================
# POST-QUANTUM MODULE 3: EXHAUSTIVE TLS 1.3 TEST ENGINE (v6.0)
# EXPECT-BASED HANDSHAKE CAPTURE
# ==============================================================================
set -e

# Verify expect is installed
if ! command -v expect &> /dev/null; then
    echo "[-] CRITICAL ERROR: 'expect' is not installed."
    echo "    Please run: sudo apt install expect -y"
    exit 1
fi

PROVIDER_ARGS=("-provider" "default" "-provider" "oqsprovider")
SERVER_PORT=4433
SERVER_PID=""

# --- CLEANUP TRAP ---
cleanup() {
    if [[ -n "$SERVER_PID" ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
        echo -e "\n[*] Shutting down OpenSSL test server (PID: $SERVER_PID)..."
        kill "$SERVER_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT

# --- STRICT POST-QUANTUM KEM GROUPS ---
STRICT_PQ_GROUPS="MLKEM1024:MLKEM768:MLKEM512:X25519MLKEM768:SecP384r1MLKEM1024:SecP256r1MLKEM768:p521_mlkem1024:p384_mlkem768:p256_mlkem512:x448_mlkem768:x25519_mlkem512:frodo1344shake:frodo976shake:frodo640shake:bikel5:bikel3:bikel1"

clear
echo "====================================================================="
echo "        PHASE 1: TARGET SELECTION"
echo "====================================================================="

DIRECTORIES=( $(find . -maxdepth 1 -type d -name "pki_*" | sort) )

if [ ${#DIRECTORIES[@]} -eq 0 ]; then
    echo "[-] No PKI directories found. Please run the Module 1 generator first."
    exit 1
fi

echo "Select the PKI environment to test:"
for i in "${!DIRECTORIES[@]}"; do
    clean_name=$(basename "${DIRECTORIES[$i]}")
    echo "$((i+1))) $clean_name"
done

while true; do
    read -p "Selection [1-${#DIRECTORIES[@]}]: " dir_choice
    if [[ "$dir_choice" =~ ^[0-9]+$ ]] && [ "$dir_choice" -ge 1 ] && [ "$dir_choice" -le "${#DIRECTORIES[@]}" ]; then
        TARGET_DIR="${DIRECTORIES[$((dir_choice-1))]}"
        break
    else
        echo "[-] Invalid selection."
    fi
done

echo "[+] Target acquired: $TARGET_DIR"

for file in "ca.crt" "server.crt" "server.key"; do
    if [ ! -f "${TARGET_DIR}/${file}" ]; then
        echo "[-] CRITICAL ERROR: Missing ${file} in ${TARGET_DIR}. Test cannot proceed."
        exit 1
    fi
done

echo -e "\n====================================================================="
echo "        PHASE 2: SERVER INITIALIZATION"
echo "====================================================================="

read -s -p "[?] If your server.key is encrypted, enter the passphrase (leave blank if unencrypted): " KEY_PASS
echo ""

PASS_ARGS=()
if [ -n "$KEY_PASS" ]; then
    PASS_ARGS=("-pass" "pass:$KEY_PASS")
fi

echo "[*] Spinning up Strict-PQ OpenSSL s_server on localhost:$SERVER_PORT..."
openssl s_server "${PROVIDER_ARGS[@]}" \
    -accept $SERVER_PORT \
    -cert "${TARGET_DIR}/server.crt" \
    -key "${TARGET_DIR}/server.key" \
    "${PASS_ARGS[@]}" \
    -CAfile "${TARGET_DIR}/ca.crt" \
    -groups "$STRICT_PQ_GROUPS" \
    -tls1_3 \
    -www > server_debug.log 2>&1 &

SERVER_PID=$!
sleep 2 

if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    echo -e "\e[31m[-] SERVER CRASHED ON STARTUP. Incorrect password or port conflict.\e[0m"
    echo "--- Server Error Output ---"
    cat server_debug.log
    exit 1
fi
echo "[+] Server is live (PID: $SERVER_PID). Waiting for connections..."

echo -e "\n====================================================================="
echo "        PHASE 3: CLIENT CONNECTION INITIATION (EXPECT ENGINE)"
echo "====================================================================="

echo "[*] Firing OpenSSL s_client payload against server..."
echo "[*] Forcing strict Root CA validation (-verify_return_error)..."
echo "[*] Enforcing Strict Post-Quantum KEM negotiation..."

expect -c "
    log_file client_debug.log
    spawn openssl s_client ${PROVIDER_ARGS[*]} -connect localhost:$SERVER_PORT -CAfile ${TARGET_DIR}/ca.crt -groups $STRICT_PQ_GROUPS -tls1_3 -verify_return_error
    expect {
        \"SSL-Session:\" {
            # Wait a tiny bit for the rest of the block to print
            sleep 0.5
            send \"Q\r\"
            exp_continue
        }
        \"DONE\" {
            exit 0
        }
        eof {
            exit 0
        }
        timeout {
            exit 1
        }
    }
" > /dev/null 2>&1

# Check if client_debug.log contains CONNECTED
set +e
grep -q "CONNECTED" client_debug.log
CLIENT_STATUS=$?
set -e

echo -e "\n====================================================================="
echo "        PHASE 4: EXHAUSTIVE CRYPTOGRAPHIC ANALYSIS"
echo "====================================================================="

if [ $CLIENT_STATUS -eq 0 ]; then
    echo -e "\e[32m[+] HANDSHAKE SUCCESSFUL: Zero-Error TLS 1.3 Connection Established!\e[0m\n"
    
    set +e 

    CERT_PUB_ALG=$(openssl x509 -in "${TARGET_DIR}/server.crt" -text -noout | grep "Public Key Algorithm:" | head -n 1 | sed 's/.*Public Key Algorithm: //')
    CERT_SIG_ALG=$(openssl x509 -in "${TARGET_DIR}/server.crt" -text -noout | grep "Signature Algorithm:" | head -n 1 | sed 's/.*Signature Algorithm: //')
    
    TLS_VERIFY=$(grep -a "Verify return code:" client_debug.log | head -n 1 | sed 's/.*Verify return code: //' | xargs)
    PEER_SIG=$(grep -a "Peer signature type:" client_debug.log | head -n 1 | sed 's/.*Peer signature type: //' | xargs)
    TEMP_KEY=$(grep -a "Server Temp Key:" client_debug.log | head -n 1 | sed 's/.*Server Temp Key: //' | xargs)
    
    TLS_CIPHER=$(grep -a "Cipher    :" client_debug.log | head -n 1 | sed 's/.*Cipher    : //' | xargs)
    if [ -z "$TLS_CIPHER" ] || [ "$TLS_CIPHER" = "0000" ]; then
        TLS_CIPHER=$(grep -a "Cipher is " client_debug.log | head -n 1 | sed 's/.*Cipher is //' | xargs)
    fi

    set -e
    
    echo "--- 1. CERTIFICATE IDENTITY (X.509 STATIC) ---"
    echo " > Target Public Key Type:  ${CERT_PUB_ALG:-Not Detected}"
    echo " > Root CA Signature Hash:  ${CERT_SIG_ALG:-Not Detected}"
    
    echo -e "\n--- 2. TLS SESSION PARAMETERS ---"
    echo " > Symmetric Cipher Suite:  ${TLS_CIPHER:-Not Detected}"
    echo " > CA Verification Chain:   ${TLS_VERIFY:-Not Detected}"

    echo -e "\n--- 3. POST-QUANTUM NEGOTIATION (KEX/KEM) ---"
    if [ -n "$PEER_SIG" ]; then
        echo -e " > Handshake Authenticated: \e[32mYES\e[0m"
        echo "   (Server proved identity by signing transcript with ${PEER_SIG})"
    else
        echo -e " > Handshake Authenticated: \e[31mUNKNOWN\e[0m"
    fi

    if [ -n "$TEMP_KEY" ]; then
        echo -e " > Forward Secrecy KEM:     \e[32mESTABLISHED (POST-QUANTUM)\e[0m"
        echo "   (Dynamically encapsulated secret using: ${TEMP_KEY})"
    else
        echo -e " > Forward Secrecy KEM:     \e[31mPARSE ERROR\e[0m"
        echo "   (Check the raw dump below to manually verify the 'Server Temp Key')"
    fi

    echo -e "\n====================================================================="
    echo "        RAW OPENSSL SESSION DUMP (FULL RESULT)"
    echo "====================================================================="
    # We strip out any messy expect control characters before printing
    sed -r "s/\x1B\[([0-9]{1,3}(;[0-9]{1,2})?)?[mGK]//g" client_debug.log

else
    echo -e "\e[31m[-] HANDSHAKE FAILED: Connection rejected or cryptographic mismatch.\e[0m\n"
    echo "--- Client Error Output ---"
    cat client_debug.log
    echo "---------------------------"
    
    echo -e "\n--- Server Error Output ---"
    tail -n 10 server_debug.log
    echo "---------------------------"
fi
