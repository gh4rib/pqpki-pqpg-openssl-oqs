# PKI and PQC-Messenger
A hobby project to implemennt PQS-CA/Cert generation and PQS Messenger using openssl 3.5+ and liboqs on Debian/13.5.

Information you need if you are not familiar with post-quantum world
- ML-DSA (Dilithium) is strictly a digital signature algorithm. It can only be used to sign and verify messages to guarantee authenticity and integrity. It cannot be used to encrypt or decrypt data. For post-quantum asymmetric encryption/decryption, you must use ML-KEM (Kyber).
- As of mid-2026, the CA/Browser Forum has not authorized public Certificate Authorities (like Let's Encrypt or ZeroSSL) to issue ML-DSA certificates, and root stores (like Windows, Apple, or Mozilla) do not trust them yet. The first publicly trusted PQ certificates aren't expected to be broadly recognized until 2027.
- What is Stateful Signature Scheme? [link](https://github.com/gh4rib/pqc-pki-messenger/blob/main/stateful-signature-scheme.md)
- What is Extendable-Output Functions ? [link](https://github.com/gh4rib/pqc-pki-messenger/blob/main/xof.md)
- What is Ascon v1.2 ? [link](https://github.com/gh4rib/pki-pqc-messenger/blob/main/ascon-vs-aes.md)

---

## Requirements
- OpenSSL 3.5+ (Debian/13.5 has this by default)
- `` apt install gcc build-essential expect xxd git ``
- Compile the Open-Quantum-Safe ``liboqs`` & ``oqs-provider`` to use them with openssl

---

## Compile liboqs & oqs-provider
- Compiling liboqs
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

- Compiling oqs-provier
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

- Add the following configuration to the ``/etc/ssl/openssl.cnf``
```bash
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

- Verify ``oqs-provider`` is loaded by running ``openssl list -providers``

---

## PQ-PKI
The post-quantum safe PKI written with bash (wrapper for OpenSSL & liboqs) using algorithms they provide along with a test engine that run a PQ Server and Client using openssl to initiate and test
the result of the script.
<strong> It is just an implementation of the whole process which is not tested thoroughly by me. I just tested one combination of the algorithms and tested them </strong>.

### Procedure
Modern X.509 Architecture Note

- **Root CA Key:** Must use an asymmetric Signature scheme (like ML-DSA, Falcon, or SLH-DSA) to allow it to sign certificates.
- **Website/Server Key:** Can either be an asymmetric Signature scheme (for classic authentication) or a KEM scheme (for key exchange optimization).
- **Symmetric Protection:** When saving private keys, the script allows you to encrypt them using ChaCha20, AES-256-CBC, or Camellia-256-CBC.
- **MACs (HMAC, SipHash, Poly1305, CMAC):** These are symmetric Message Authentication Codes and do not utilize asymmetric public/private keys; therefore, they cannot be embedded into X.509 certificates. They are omitted from the certificate menu but noted for symmetric data integrity.

### The ``pki-engine-script``
- The script guide you and create a folder containing ``ca.cert,ca.key,server.crt,server.key,server.pub``
The Folder Naming Convention
- I set up a rule to automatically name the output folder based on the exact algorithms you chose during the interactive menu, formatted as:
``pki_[Root_CA_Algorithm]_[Server_Algorithm]``

### The ``pki-engine-test-script``
This is how we evaluate our TLS connection. Simply knowing the connection "worked" is not enough; we need to dissect the handshake, verify the certificate identity, and prove that the Key Encapsulation Mechanism (KEM) actually established.

The script inspects both the generated server.crt file on disk and the live telemetry from the OpenSSL session. It cross-references them to build a comprehensive, beautifully formatted Cryptographic Test Report.

It extracts the exact Protocol, Symmetric Cipher, End-Entity Key algorithms, Peer Signature schemes, and the specific Ephemeral KEM used to encapsulate the shared secret. Finally, it prints the raw OpenSSL session dump for your absolute full result.

The following is a sample result:
```bash

=====================================================================
        RAW OPENSSL SESSION DUMP (FULL RESULT)
=====================================================================
spawn openssl s_client -provider default -provider oqsprovider -connect localhost:4433 -CAfile ./pki_mldsa87_mldsa87/ca.crt -groups MLKEM1024:MLKEM768:MLKEM512:X25519MLKEM768:SecP384r1MLKEM1024:SecP256r1MLKEM768:p521_mlkem1024:p384_mlkem768:p256_mlkem512:x448_mlkem768:x25519_mlkem512:frodo1344shake:frodo976shake:frodo640shake:bikel5:bikel3:bikel1 -tls1_3 -verify_return_error
Connecting to ::1
CONNECTED(00000003)
Can't use SSL_get_servername
depth=1 O=PQ Laboratory, CN=Quantum Safe CA
verify return:1
depth=0 O=Secure Target Node, CN=secure.local
verify return:1
---
Certificate chain
 0 s:O=Secure Target Node, CN=secure.local
   i:O=PQ Laboratory, CN=Quantum Safe CA
   a:PKEY: ML-DSA-87, 20736 (bit); sigalg: ML-DSA-87
   v:NotBefore: May 30 17:12:24 2026 GMT; NotAfter: May 30 17:12:24 2027 GMT
 1 s:O=PQ Laboratory, CN=Quantum Safe CA
   i:O=PQ Laboratory, CN=Quantum Safe CA
   a:PKEY: ML-DSA-87, 20736 (bit); sigalg: ML-DSA-87
   v:NotBefore: May 30 17:12:24 2026 GMT; NotAfter: May 27 17:12:24 2036 GMT
---
Server certificate
-----BEGIN CERTIFICATE-----
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
AAAAAAAAAAAAAAAAAAAAAAAGCxQbICkuMQ==
-----END CERTIFICATE-----
subject=O=Secure Target Node, CN=secure.local
issuer=O=PQ Laboratory, CN=Quantum Safe CA
---
No client certificate CA names sent
Peer signature type: mldsa87
Negotiated TLS1.3 group: MLKEM1024
---
SSL handshake has read 21509 bytes and written 1950 bytes
Verification: OK
---
New, TLSv1.3, Cipher is TLS_AES_256_GCM_SHA384
Protocol: TLSv1.3
Server public key is 20736 bit
This TLS version forbids renegotiation.
Compression: NONE
Expansion: NONE
No ALPN negotiated
Early data was not sent
Verify return code: 0 (ok)
---
---
Post-Handshake New Session Ticket arrived:
SSL-Session:
    Protocol  : TLSv1.3
    Cipher    : TLS_AES_256_GCM_SHA384
    Session-ID: 717AF461E50C59FABFB89C1DA21937461D871A28570F9507CD080148CB35AF5B
    Session-ID-ctx: 
    Resumption PSK: C172837F3D556043DDF74E09E3CB65B04D17AD13951BF240D1D4002A007C13B7DA56C651CCF9C8C1D40D45940485CB0A
    PSK identity: None
    PSK identity hint: None
    SRP username: None
    TLS session ticket lifetime hint: 7200 (seconds)
    TLS session ticket:
    0000 - f4 7c 47 43 5e 1a 13 da-19 60 9e 2d 2e 9c 28 ae   .|GC^....`.-..(.
    0010 - 1d 7b ee 85 28 e1 83 55-79 6b 6e 5c 30 db 50 61   .{..(..Uykn\0.Pa
    0020 - 82 a2 6b 5e 0f 75 ee 37-59 fc 31 26 d9 73 a0 3b   ..k^.u.7Y.1&.s.;
    0030 - 62 6d bf d2 9d 70 a6 9d-c5 de f4 fc 5b 39 8c 53   bm...p......[9.S
    0040 - e5 3e a5 fc dc c9 ea 5a-02 2b 69 08 cb 0f ec 6f   .>.....Z.+i....o
    0050 - 50 de 87 0b 1f b5 4d 1d-36 bc 01 7c cf 70 85 4a   P.....M.6..|.p.J
    0060 - a2 6e 96 54 04 0b 6c ad-6d 39 fc 9f 70 fd d1 45   .n.T..l.m9..p..E
    0070 - 8f 40 ea 19 d5 40 36 60-19 95 ed 5f e8 e5 28 89   .@...@6`..._..(.
    0080 - 8d 9f ef 12 dd 1b e1 6c-ed ed 56 7b a6 e7 04 22   .......l..V{..."
    0090 - 43 a6 f8 d5 b7 c8 2e 9c-32 72 76 52 34 f1 32 94   C.......2rvR4.2.
    00a0 - 59 e1 c5 f8 48 6e 20 f4-63 f8 ca c3 c6 7e 76 0e   Y...Hn .c....~v.
    00b0 - 75 0f 2a 4c e0 11 d5 b0-f4 bc d8 52 36 7e d5 aa   u.*L.......R6~..
    00c0 - 67 9f a0 55 92 a4 99 3a-3b 50 8f 09 a9 85 05 95   g..U...:;P......

    Start Time: 1780172084
    Timeout   : 7200 (sec)
    Verify return code: 0 (ok)
    Extended master secret: no
    Max Early Data: 0
---
read R BLOCK
---
Post-Handshake New Session Ticket arrived:
SSL-Session:
    Protocol  : TLSv1.3
    Cipher    : TLS_AES_256_GCM_SHA384
    Session-ID: C698193C7889F9429D2CBC3B7332596B489CBBDE9ECAE3E9EF1E06071F23146C
    Session-ID-ctx: 
    Resumption PSK: 93936343757B7273A42652E3BEA174FD3E54DD314584FC29E53D2AEBEF1ACEF948DF052A3F642CC3785980FF1B1D67EF
    PSK identity: None
    PSK identity hint: None
    SRP username: None
    TLS session ticket lifetime hint: 7200 (seconds)
    TLS session ticket:
    0000 - f4 7c 47 43 5e 1a 13 da-19 60 9e 2d 2e 9c 28 ae   .|GC^....`.-..(.
    0010 - aa 58 d7 ea 8e 42 b4 5a-1f a2 f2 06 01 85 06 40   .X...B.Z.......@
    0020 - ed 55 80 87 7b 73 41 27-75 40 a5 11 b8 1d 12 68   .U..{sA'u@.....h
    0030 - f9 46 cb fb 4e 75 44 00-a9 1b 1b 3b 7c da 25 57   .F..NuD....;|.%W
    0040 - 5d 9c c8 c3 6c d3 5e 3b-ee 7c 32 5c 77 03 62 71   ]...l.^;.|2\w.bq
    0050 - 30 78 81 64 c1 04 57 1f-43 98 ff 66 85 a5 e4 06   0x.d..W.C..f....
    0060 - dd ee 7d d8 2f ad a7 b3-00 41 f3 5e db 43 35 e0   ..}./....A.^.C5.
    0070 - 5b 9d 2a a7 c1 ee 24 0b-80 19 3b ea 8d 59 af a7   [.*...$...;..Y..
    0080 - 2b a7 4d 68 ae 66 b7 43-9c fd af 67 96 a5 4a b8   +.Mh.f.C...g..J.
    0090 - 33 bb d7 4d ad 0b c6 77-38 aa f9 f2 39 d1 25 c3   3..M...w8...9.%.
    00a0 - ca 0b 89 fd 09 b9 2a bd-78 f3 e4 dd 9c f6 07 47   ......*.x......G
    00b0 - 2a 6a 74 1a c5 2d c7 71-3d e7 01 63 83 06 18 65   *jt..-.q=..c...e
    00c0 - d9 4d ba 30 50 81 28 47-f0 3b fc 5b 5b 5e 5b eb   .M.0P.(G.;.[[^[.

    Start Time: 1780172084
    Timeout   : 7200 (sec)
    Verify return code: 0 (ok)
    Extended master secret: no
    Max Early Data: 0
---
read R BLOCK
Q
DONE

```

---

## PQC Simple Messenger
A Simple mirror (probably not safe for production usage) of signalMessenger and protonMail.

### The "Signal/Proton" Architecture Here

1. **The Key Generation (Identity Setup)**
Just like setting up a ProtonMail account, you generate two distinct keys:

- **The Identity Key (DSA):** E.g., ``MLDSA87``. Used only to sign messages to prove you wrote them.
- **The Envelope Key (KEM):** E.g., ``MLKEM1024``. Used only to allow other people to encapsulate a secret that only you can open.

2. **The Sending Process (Encrypt-then-Sign via AEAD)**
When you send a file to Bob, the script does exactly what Signal does:

- **KEM Encapsulation:** It uses Bob's public MLKEM key to generate a random 256-bit Shared Secret (the ephemeral session key).
- **Symmetric AEAD Encryption:** It uses that Shared Secret to encrypt your message using a military-grade AEAD cipher (like ``aes-256-gcm`` or ``chacha20-poly1305``). Crucially, AEAD ciphers generate an Authentication Tag. This tag mathematically proves the ciphertext has not been tampered with.
- **The Digital Signature:** It calculates a strong hash `e.g., ``SHA3-512`` or ``KECCAK-512``) of the ciphertext and the AEAD Tag, and signs that hash with your private MLDSA key.

3. **The Receiving Process (Verify-then-Decrypt)**
When Bob receives the folder, the script reverses the process in strict order to prevent cryptographic attacks (like Padding Oracles):
- **Identity Verification:** It verifies the signature against the hash of the ciphertext. If it fails, it drops the file immediately.
- **KEM Decapsulation:** It uses Bob's private MLKEM key to extract the 256-bit Shared Secret.
- **AEAD Integrity Check & Decrypt:** It passes the Shared Secret, Ciphertext, and AEAD Tag into the symmetric cipher. If the tag doesn't match, decryption fails. If it matches, you get the plaintext.

4. **A Double Ratchet algorithm (like Signal)**
Every time you send a message, generate a brand new ephemeral KEM keypair, attach the public key to the message, and use it to negotiate a new shared secret.
This guarantees Perfect Forward Secrecy (PFS) and Post-Compromise Security (PCS).

### My Architecture
**The OpenSSL Problem** : 
In standard OpenSSL, when you use a block cipher like aes-256-cbc, it encrypts the file and exits gracefully.

However, with AEAD ciphers like aes-256-gcm, OpenSSL has to do two things simultaneously:
- Write the ciphertext to ``payload.cipher``.
- Extract the Authentication MAC and write it to ``payload.tag`` using standard output (the ``> payload.tag`` part of the command).

I changed the architecture a little bit! I have used the Encrypt-then-MAC architecture. This is precisely how the Signal Protocol (v2) and IPsec establish Authenticated Encryption.

Instead of asking OpenSSL to do the encryption and the tagging in one step, I have separated them:
- I use the KEM Secret to generate two keys: an Encryption Key and a MAC Key.
- I encrypt the payload using a rock-solid standard cipher (aes-256-cbc or chacha20).
- I explicitly calculate a Hash-based Message Authentication Code (HMAC) over the ciphertext. This serves as our mathematically perfect AEAD Tag.
- I sign the whole bundle with the Post-Quantum Identity.

In addition to this I implemented the following capabilities into the script
- SPHINCS+ (SLH-DSA): The most mathematically conservative hash-based signature scheme in existence, perfect for long-term Root Identity.
- Hybrid Key Exchange (X25519 + ML-KEM): Implementing a true safety net where an attacker must break both classic elliptic curves and quantum lattices to read your messages.
- Cryptographic Fingerprinting: Giving the user the ability to generate short, verifiable hashes of the giant public keys to share on Social Platforms.

**Note on the Double Ratchet: Implementing a full asynchronous Double Ratchet algorithm like Signal in a stateless bash script is architecturally impossible because it requires maintaining synchronous state chains (Root Chain, Sending Chain, Receiving Chain) across multiple file executions. However, I have implemented Ephemeral Hybrid Forward Secrecy per message, which is the foundational step of the Ratchet.**

### The flow of Messaging (High-Level)
Exact flow requires a tiny bit of coordination between you and your friend.

Here is the exact, step-by-step procedure of how you and a friend (let's call him Bob) will use this engine in the real world:

#### Step 1: Establish Identities (Both Users)

- **You:** Run the script, select **Option 1**, and create `identity_daud`.
- **Bob:** Runs the script on his computer, selects **Option 1**, and creates `identity_bob`.

#### Step 2: The Key Exchange (Public Sharing)

- You send Bob your **Public Keyring Folder** (`./identity_daud/public/`).
- Bob sends you his **Public Keyring Folder** (`./identity_bob/public/`).
- (Note: You can send these folders over email, USB drive, or host them on a website. They are 100% public and safe to share).

#### Step 3: Fingerprint Verification (Crucial Security Step)
- You run **Option 2** (Generate Cryptographic Fingerprints) on Bob's public folder to get the short hashes.
- You text/call Bob: **"Hey Bob, I got your keys. Is this your Signature Fingerprint a1:b2:c3....?"**
- If he says yes, you know the keys are authentic.

#### Step 4: Encrypt & Sign (Sending)

Now you want to send Bob a secret message (`message1.txt`).
- You run **Option 3** (Encrypt & Sign).
- When the script asks for **YOUR Private Keyring**, you point it to `./identity_daud/private`. (This allows you to sign the message).
- When the script asks for the **RECIPIENT'S Public Keyring**, you point it to the `./identity_bob/public` folder he gave you in Step 2. (This locks the message so only Bob can read it).
- The script spits out a locked folder: `outbox_msg_2026...`

#### Step 5: Transmission

- You send that `outbox_msg` folder to Bob over email, Telegram, or a USB drive. Even if the NSA intercepts it, they cannot read it.

#### Step 6: Decrypt & Verify (Receiving)

Bob receives your locked folder.

- He runs **Option 4** (Decrypt & Verify).
- When the script asks for **HIS Private Keyring**, he points it to `./identity_bob/private`. (This unlocks the KEM).
- When the script asks for the **SENDER'S Public Keyring**, he points it to the `./identity_daud/public` folder you gave him in Step 2. (This verifies your signature).
- The script safely spits out `decrypted_message.txt`.

### The flow of Messaging (Low-Level)
The script **strictly verifies the signature** before **doing anything** else during decryption. If the signature is invalid (meaning the message was tampered with, or the sender is an imposter), the script instantly throws a red `CRITICAL` alert and hard-exits, refusing to decrypt the payload. This prevents attackers from feeding your KEM malicious data.


#### Option 1: Identity Generation Architecture

This phase creates your long-term cryptographic identity. Because we are using a **Hybrid** architecture, you actually generate three separate mathematical keys.

1. **The Classical Routing Key (X25519):**
- **Purpose:** A proven, fast Elliptic Curve Diffie-Hellman (ECDH) key. This acts as our classical safety net.
- **Math:** `openssl genpkey -algorithm X25519`


2. **The Post-Quantum Routing Key (ML-KEM):**
- **Purpose:** A lattice-based Key Encapsulation Mechanism. This protects against Future Quantum Computers (Store Now, Decrypt Later attacks).
- **Math:** `openssl genpkey -algorithm MLKEM1024`


3. **The Identity Key (SLH-DSA / SPHINCS+):**
- **Purpose:** A hyper-conservative, hash-based digital signature algorithm. You use this to "sign" your messages to prove you wrote them.
- **Math:** `openssl genpkey -algorithm SLH-DSA-SHA2-256s`



**Output State:** You now have a `./private` folder (which you guard with your life) and a `./public` folder (which you share with the world).


#### Option 3: Encryption & Signing Architecture (The Sender)

This is the most complex phase. It implements a true **Hybrid KEX + Encrypt-then-MAC** pipeline. Assume Alice is sending a message to Bob.

1. **Hybrid Key Exchange (KEX):**
- Alice takes Bob's public `X25519` key and her private `X25519` key to mathematically derive a 32-byte shared secret (`classic_secret.bin`).
- Alice uses Bob's public `ML-KEM` key to encapsulate a random 32-byte post-quantum secret (`pq_secret.bin`). She must send the resulting "capsule" (`pq_payload.encap`) to Bob.


2. **Key Derivation Function (KDF):**
- Alice concatenates the two secrets: `[Classic 32B] + [PQ 32B]`.
- She hashes them together using SHA-512 to create a master 64-byte secret string.
- She splits it: The first 32 bytes become the **AES Encryption Key** (`HEX_KEY`). The second 32 bytes become the **HMAC Authentication Key** (`MAC_KEY`).


3. **Symmetric Encryption (The Payload):**
- Alice generates a random 16-byte Initialization Vector (IV).
- She encrypts her message using `aes-256-cbc` and the `HEX_KEY`. This creates the `payload.cipher`.


4. **The AEAD Authentication Tag (HMAC):**
- Alice hashes the `payload.cipher` using SHA-256, keyed with her `MAC_KEY`. This creates the `payload.tag`. This tag mathematically proves the ciphertext has not been altered.


5. **The Digital Signature (Identity Proof):**
- Alice concatenates the Ciphertext, the IV, the Tag, and *her public X25519 key* into a single bundle.
- She signs that bundle using her private `SLH-DSA` key to create `payload.sig`.
- **(Note: She includes her public X25519 key in the signature so Bob knows exactly who to derive the classical secret with, preventing Man-in-the-Middle attacks).**



**Output State:** Alice sends Bob a folder containing: `payload.cipher`, `payload.iv`, `payload.tag`, `payload.sig`, `pq_payload.encap`, and `sender_x25519.pub`.


#### Option 4: Decryption & Verification Architecture (The Receiver)

This phase strictly reverses the encryption steps. **Crucially, it verifies authenticity before attempting any decryption.**

1. **Identity Verification (The Gatekeeper):**
- Bob re-creates the exact same bundle Alice signed (Ciphertext + IV + Tag + Sender's X25519 Pubkey).
- He uses Alice's public `SLH-DSA` key to verify `payload.sig`.
- **SECURITY CHECK:** If this fails, the script immediately prints a red `CRITICAL` error and exits. The sender is fake or the message was tampered with in transit.


2. **Hybrid Key Decapsulation:**
- Bob uses his private `X25519` key and Alice's provided public `X25519` key to derive the `classic_secret.bin`.
- Bob uses his private `ML-KEM` key to open the `pq_payload.encap` and extract the `pq_secret.bin`.


3. **Key Derivation Function (KDF):**
- Bob performs the exact same hash (SHA-512) on the combined secrets to regenerate the `HEX_KEY` and the `MAC_KEY`.


4. **AEAD Integrity Check:**
- Bob calculates his own HMAC over the `payload.cipher` using the derived `MAC_KEY`.
- He compares his calculated tag against the `payload.tag` Alice sent.
- **SECURITY CHECK:** If they do not match exactly, the script prints a red `CRITICAL` error and exits. The ciphertext is corrupt.


5. **Payload Decryption:**
- Because both the Signature and the HMAC Tag are mathematically proven valid, Bob finally decrypts `payload.cipher` using the `HEX_KEY` and `HEX_IV`.
- The plaintext `decrypted_message.txt` is written to disk.

