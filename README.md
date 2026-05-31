# PKI and PQC-Messenger

A hobby project to implement PQS-CA/Cert generation and PQS Messenger (It is not an actual messenger like Signal 🙂) using OpenSSL 3.5+ and liboqs on Debian 13.5.

### Information you need if you are not familiar with the post-quantum world:

- **ML-DSA (Dilithium)** is strictly a digital signature algorithm. It can only be used to sign and verify messages to guarantee authenticity and integrity. It cannot be used to encrypt or decrypt data. For post-quantum asymmetric encryption/decryption, you must use **ML-KEM (Kyber)**.
- As of mid-2026, the CA/Browser Forum has not authorized public Certificate Authorities (like Let's Encrypt or ZeroSSL) to issue ML-DSA certificates, and root stores (like Windows, Apple, or Mozilla) do not trust them yet. The first publicly trusted PQ certificates aren't expected to be broadly recognized until 2027.
- What is a Stateful Signature Scheme? [link](https://github.com/gh4rib/pqc-pki-messenger/blob/main/stateful-signature-scheme.md)
- What are Extendable-Output Functions? [link](https://github.com/gh4rib/pqc-pki-messenger/blob/main/xof.md)
- What is Ascon v1.2? [link](https://github.com/gh4rib/pki-pqc-messenger/blob/main/ascon-vs-aes.md)

---

## Requirements

- OpenSSL 3.5+ (Debian 13.5 has this by default)
- `apt install gcc build-essential expect xxd git`
- Compile the Open-Quantum-Safe `liboqs` & `oqs-provider` to use them with OpenSSL.

---

## Compile liboqs & oqs-provider

### Compiling liboqs

```bash
git clone -b main https://github.com/open-quantum-safe/liboqs.git
cd liboqs
mkdir build && cd build

# Configure and build
cmake -GNinja -DBUILD_SHARED_LIBS=ON -DOQS_ALGS_ENABLED=All -DOQS_ENABLE_SIG_STFL_LMS=ON -DOQS_ENABLE_SIG_STFL_XMSS=ON -DOQS_HAZARDOUS_EXPERIMENTAL_ENABLE_SIG_STFL_KEY_SIG_GEN=ON ..
ninja

# Generate the .deb package
ninja package

# Install the generated package (e.g., liboqs-0.15.0-Linux.deb)
sudo apt install -y ./*.deb

# Update the linker cache so the next build finds liboqs.so
sudo ldconfig

```

### Compiling oqs-provider

```bash
git clone -b main https://github.com/open-quantum-safe/oqs-provider.git
cd oqs-provider

# Configure and build
cmake -S . -B _build
cmake --build _build
cd _build

# Run tests to ensure it linked correctly to liboqs and OpenSSL
ctest --parallel 4 --rerun-failed --output-on-failure -V

# Generate the .deb package
make package

# Install the generated package
sudo apt install -y ./*.deb

```

### OpenSSL Configuration

Add the following configuration to `/etc/ssl/openssl.cnf`:

```ini
[openssl_init]
providers = provider_sect

[provider_sect]
default = default_sect
oqsprovider = oqsprovider_sect

[default_sect]
activate = 1

[oqsprovider_sect]
activate = 1

```

Verify `oqs-provider` is loaded by running `openssl list -providers`.

---

## PQ-PKI

The post-quantum safe PKI written with bash (wrapper for OpenSSL & liboqs) using the algorithms they provide, along with a test engine that runs a PQ Server and Client using OpenSSL to initiate and test the result of the script.

**It is just an implementation of the whole process which is not tested thoroughly by me. I just tested one combination of the algorithms and tested them.**

### Procedure: Modern X.509 Architecture Note
- **Root CA Key:** Must use an asymmetric Signature scheme (like ML-DSA, Falcon, or SLH-DSA) to allow it to sign certificates.
- **Website/Server Key:** Can either be an asymmetric Signature scheme (for classic authentication) or a KEM scheme (for key exchange optimization).
- **Symmetric Protection:** When saving private keys, the script allows you to encrypt them using ChaCha20, AES-256-CBC, or Camellia-256-CBC.
- **MACs (HMAC, SipHash, Poly1305, CMAC):** These are symmetric Message Authentication Codes and do not utilize asymmetric public/private keys; therefore, they cannot be embedded into X.509 certificates. They are omitted from the certificate menu but noted for symmetric data integrity.

### The `pki-engine-script`

The script guides you and creates a folder containing `ca.cert`, `ca.key`, `server.crt`, `server.key`, and `server.pub`.
**Folder Naming Convention:** I set up a rule to automatically name the output folder based on the exact algorithms you chose during the interactive menu, formatted as: `pki_[Root_CA_Algorithm]_[Server_Algorithm]`

### The `pki-engine-test-script`

This is how we evaluate our TLS connection. Simply knowing the connection "worked" is not enough; we need to dissect the handshake, verify the certificate identity, and prove that the Key Encapsulation Mechanism (KEM) actually established.

The script inspects both the generated `server.crt` file on disk and the live telemetry from the OpenSSL session. It cross-references them to build a comprehensive, beautifully formatted Cryptographic Test Report. It extracts the exact Protocol, Symmetric Cipher, End-Entity Key algorithms, Peer Signature schemes, and the specific Ephemeral KEM used to encapsulate the shared secret. Finally, it prints the raw OpenSSL session dump for your absolute full result.

---

## PQC Simple Messenger

A simple mirror (probably not safe for production usage) of Signal Messenger and ProtonMail's cryptographic architecture.

### Advanced Obfuscation & OpenPGP-Style Enhancements (v8.5)

To defeat network-level traffic analysis and metadata tracking, this engine implements three advanced obfuscation techniques inspired by the RFC 9580 OpenPGP standard:

1. **Packet Stream Serialization (ASCII Armor):** Instead of exposing a folder full of loose cryptographic files (`payload.cipher`, `payload.tag`, etc.), the engine bundles all components into a single, continuous Base64-encoded stream. The output is a single `.pqp` text file. To an outside observer, it is just a solid wall of meaningless text.
2. **The "Literal Data" Enclave (Hiding Metadata):** Original filenames and file sizes are highly sensitive metadata. Before encryption occurs, the script prepends the original filename and exact byte length to the raw data block. This enclave is then encrypted *inside* the payload, making it entirely invisible to network interceptors.
3. **Traffic Padding (Defeating Size Analysis):** If you send a 5-byte message, the resulting ciphertext will be visibly small. An attacker can use ciphertext size to guess what you are doing. To prevent this, the engine appends thousands of random null bytes to your message, padding it to uniform 4096-byte boundaries *before* encryption. When decrypted, the parser safely strips this padding away using the hidden Literal Data Enclave headers.

### The "Signal/Proton" Architecture Here

#### 1. The Key Generation (Identity Setup)

Just like setting up a ProtonMail account, you generate distinct keys:

- **The Identity Key (DSA):** E.g., `MLDSA87`. Used only to sign messages to prove you wrote them.
- **The Envelope Key (KEM):** E.g., `MLKEM1024`. Used only to allow other people to encapsulate a secret that only you can open.
- **The Classical Routing Key (X25519):** Used alongside the PQ KEM to establish a Hybrid safety net.

#### 2. The Sending Process (Hybrid KEX + Encrypt-then-MAC)

When you send a file to Bob, the script does exactly what modern protocols do:

- **Hybrid Encapsulation:** It uses Bob's public X25519 and MLKEM keys to generate a Hybrid Shared Secret.
- **Symmetric Encryption:** It uses that Shared Secret to encrypt your padded payload enclave using a strong cipher (like `aes-256-cbc` or `chacha20`).
- **HMAC Integrity:** It explicitly calculates a Hash-based Message Authentication Code (HMAC) over the ciphertext to mathematically prove it has not been tampered with.
- **The Digital Signature:** It calculates a strong hash of the entire bundle (Ciphertext + IV + Tag + Sender Pubkey) and signs it with your private MLDSA or SLH-DSA key.

#### 3. The Receiving Process (Verify-then-Decrypt)

When Bob receives the `.pqp` armored packet, the script reverses the process in strict order to prevent cryptographic attacks (like Padding Oracles):

- **Identity Verification:** It verifies the signature against the bundle. **If it fails, it drops the file immediately.** This prevents attackers from feeding your KEM malicious data.
- **KEM Decapsulation:** It uses Bob's private keys to extract the Shared Secret.
- **HMAC Integrity Check:** It calculates the HMAC of the payload. If the tag doesn't match, decryption fails.
- **Decrypt & Extract:** It decrypts the payload, reads the Literal Data Enclave header, strips the traffic padding, and restores the pristine original file.

### The Flow of Messaging (Step-by-Step)

Exact flow requires a tiny bit of coordination between you and your friend.

1. **Establish Identities:** You and your friend run **Option 1** to create your identity keyrings (`./identity_alice` and `./identity_bob`).
2. **Public Exchange:** You swap your `./public/` folders out-of-band.
3. **Fingerprint Verification:** Run **Option 2** on your friend's public folder. Call/text them and say: *"Hey, is your Signature Fingerprint a1:b2:c3...?"* If yes, the keys are authentic.
4. **Encrypt & Sign:** Run **Option 3**. Provide your private folder (to sign) and your friend's public folder (to lock). The script generates a single ASCII-armored packet: `msg_20260531_120000.pqp`.
5. **Transmission:** Send the `.pqp` file over any channel. It is entirely padded, serialized, and safe from traffic analysis.
6. **Decrypt & Verify:** Your friend receives the `.pqp` file and runs **Option 4**. They provide their private folder (to unlock) and your public folder (to verify your identity). The script safely restores `decrypted_message.txt`.

### The Cryptographic Packet Dependency Map

Because the message is now serialized into a single `.pqp` packet stream, all components are inextricably bound together. If a single block is altered or goes missing during transmission, the math breaks:

| Packet Component | Mathematical Role | What happens if tampered/missing? |
| --- | --- | --- |
| `---ENCAP---` | Contains the wrapped KEM secret. | Recipient cannot derive the "Master Key." |
| `---CIPHERTEXT---` | The encrypted, padded payload. | Obviously, the message is gone. |
| `Header (IV)` | Initialization Vector. | Decryption will produce gibberish. |
| `---TAG---` | HMAC/AEAD Tag. | Script triggers a **Critical Error** and refuses to decrypt. |
| `---SIG---` | The Post-Quantum Signature. | Script triggers a **Critical Error** and refuses to process. |
| `---SENDER-PUB---` | The Hybrid Safety Net. | Recipient cannot derive the classical half of your hybrid key. |

---

## PQC-Messenger (Golang Edition)

A prototype, crypto-agile, Post-Quantum Cryptographic (PQC) file messenger built in Go 1.25. 

This engine utilizes a **Hybrid KEM Architecture** (Classical Elliptic Curve + Lattice-based Cryptography) and a strict **Hash-and-Sign** paradigm to guarantee NIST Level 5 quantum resistance, seamless file transmission, and absolute memory safety across the CGO boundary.

### Features

- **Crypto-Agility:** Dynamically swap Key Encapsulation Mechanisms (KEMs), Digital Signatures, Hash functions, and Symmetric Ciphers based on recipient profiles.
- **Hybrid Key Exchange:** Combines classical `X25519` with Post-Quantum KEMs to ensure security against both traditional and quantum adversaries.
- **Strict Memory Sanitization:** Utilizes `oqs.MemCleanse()` to aggressively zero-out lattice secrets and master keys from RAM to prevent cold-boot and memory scraping attacks.
- **CGO Boundary Protection:** Implements deep-copy byte cloning (`cloneBytes`) and a fixed-length Hash-and-Sign digest pipeline to prevent Go garbage-collector pointer corruption and dangling C-memory wipes.
- **Air-Gapped PKI:** Generates offline public/private keyrings for secure, file-based identity routing.

### Supported Cryptographic Primitives

The engine interfaces natively with the C-based `liboqs` to support the latest FIPS 204/205 drafts and conservative pre-standardization algorithms:

| Category | Supported Algorithms |
| :--- | :--- |
| **Post-Quantum KEM** | `ML-KEM-768`, `ML-KEM-1024`, `NTRU-HPS-4096-1229`, `Kyber1024` |
| **Classical KEM** | `X25519` (ECDH) |
| **PQ Digital Signatures** | `ML-DSA-65`, `ML-DSA-87`, `SLH_DSA_PURE_SHA2_256S`, `Falcon-1024` |
| **Symmetric AEAD** | `AES-256-GCM`, `ChaCha20-Poly1305` |
| **Key Derivation (KDF)** | `SHA-384`, `SHA-512`, `SHAKE-256` (Sponge XOF) |

### Prerequisites

- **Go 1.25+** (Required for the latest `crypto` and `hash` interface optimizations).
- **liboqs:** The Open Quantum Safe C library must be compiled and installed on your system.
- **liboqs-go:** The Golang wrapper for `liboqs`.

Ensure your CGO environment variables are configured to point to your `liboqs` build:
```bash

sudo mkdir -p /usr/local/lib/pkgconfig

sudo tee /usr/local/lib/pkgconfig/liboqs-go.pc > /dev/null << 'EOF'
LIBOQS_INCLUDE_DIR=/usr/local/include
LIBOQS_LIB_DIR=/usr/local/lib

Name: liboqs-go
Description: liboqs CGO pkg-config file for Go bindings
Version: 0.15.0
Cflags: -I${LIBOQS_INCLUDE_DIR}
Libs: -L${LIBOQS_LIB_DIR} -loqs
EOF

export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig:$PKG_CONFIG_PATH
export LD_LIBRARY_PATH=/usr/local/lib:$LD_LIBRARY_PATH
export CGO_CFLAGS="-I/usr/local/include -I/usr/include"
export CGO_LDFLAGS="-L/usr/local/lib -L/usr/lib/x86_64-linux-gnu -loqs"

go get github.com/open-quantum-safe/liboqs-go/oqs
```

### Installation & Build

Clone the repository and build the interactive CLI binary:

```bash
cd pqc-messaging-go
go mod tidy
go build -o pqc-messenger main.go

```

### Usage Guide

Launch the interactive CLI:

```bash
./pqc-messenger

```

### 1. Establish an Identity (PKI Setup)

Select **Option 1** to generate a new offline keypair. You will be prompted to choose a security profile (e.g., NIST Level 5 `ML-KEM-1024` + `ML-DSA-87`).

- This creates two folders: `./keys_name/private` (Keep Secret) and `./keys_name/public` (Share with friends).
- The `profile.json` inside dictates your preferred routing algorithms.

### 2. Encrypt & Sign a File (Send)

Select **Option 2** to encrypt a payload for a recipient.

- **Inputs needed:** Path to your private folder, path to the recipient's public folder, and the file you wish to send (e.g., `secret.pdf`).
- **Output:** Generates an `outbox_msg.pqp` (Post-Quantum Packet) containing the serialized JSON envelope.

### 3. Decrypt & Verify a File (Receive)

Select **Option 3** to verify the cryptographic signature and decrypt the payload.

- **Inputs needed:** Path to your private folder, path to the sender's public folder, and the `.pqp` packet.
- **Output:** Upon mathematical verification of the signature and AEAD MAC tag, the engine outputs the decrypted file with a precise timestamp (e.g., `decrypted_msg_20260531_150405.txt`).

## Security Architecture Notes

This framework addresses several notorious issues in Post-Quantum integration:

1. **Dangling Pointers:** The `liboqs` C library aggressively frees memory structures. My `cloneBytes` function ensures that extracted lattice keys are safely ported into Go's garbage-collected heap before the C thread terminates.
2. **Fiat-Shamir Sensitivity:** Algorithms like ML-DSA are highly sensitive to data serialization. My engine constructs a rigid byte-bundle combining the routing suite, ciphertext, nonce, and sender public key, strictly hashing it via `SHA-512` before passing it to the signature engine. This "Authenticated Negotiation" ensures an attacker cannot silently downgrade the cipher suite inside the JSON.

---

## Beyond this Simple/Hobby Project

I plan to implement a proper, stateful application using Golang (`cloudflare/circl`) in the future.

**Why transition away from Bash and OpenSSL CLI?**
While this bash engine successfully implements Encrypt-then-MAC and Hybrid KEX, the OpenSSL command-line interface has hard limits. It is stateless (meaning we cannot maintain synchronous key chains in memory to implement the **Double Ratchet** for true per-message Perfect Forward Secrecy) and it struggles with complex pipeline deadlocks when manipulating raw AEAD tags.

By moving to Golang and `circl`:

1. We gain memory safety to hold "Session State" for the Double Ratchet.
2. We gain type-safe manipulation of native Post-Quantum data structures.
3. We cleanly separate the architecture into two distinct modules: a **PKI Engine** (strictly for Identity Lifecycle, Root CA, and Fingerprinting) and a **PQC-Messenger** (strictly for Transport, ephemeral Session Key rotation, and Payload bundling).

*(Alternatively, users looking for standardized integrations can monitor the experimental `gnupg 2.5+` development branch to generate ML-KEM keys directly within the LibrePGP ecosystem, though broad compatibility remains limited.)*
