A stateful signature scheme is a type of digital signature where the private key strictly updates its internal state—usually by incrementing a counter or index—every single time a signature is generated.

Unlike conventional algorithms (like RSA, ECDSA, or the post-quantum ML-DSA) where you can use the exact same static private key to sign millions of messages safely, a stateful private key mathematically changes with every use.

These are entirely **Hash-Based Signature (HBS)** schemes. They do not rely on hard mathematical problems like factoring or lattices; they rely purely on the collision resistance of standard hash functions like SHA-256 or SHAKE.

### How They Work

Stateful signatures are built by combining two concepts: **One-Time Signatures (OTS)** and **Merkle Trees**.

1. **The Leaf Nodes (OTS):** At the core is a one-time signature scheme (typically Winternitz OTS). An OTS private key is incredibly fast and secure, but it can only be used to sign exactly **one** message. If you use it twice, an attacker can reverse-engineer the key from the overlapping signature data.
2. **The Tree:** To make OTS practical, you generate a massive number of OTS keypairs (e.g., $2^{20}$, or about 1 million). You hash all of their public keys and pair them up to form a massive binary Merkle tree.
3. **The Public Key:** The single root hash at the very top of that tree becomes your global public key.
4. **The Signature:** When you sign a message, you use one of the OTS private leaves. The final signature contains the OTS signature, plus the authentication path (the sibling hashes) up the tree so the verifier can prove that specific leaf belongs to the root public key.

### Why the "State" is Critical (and Dangerous)

The "state" is essentially a pointer keeping track of which OTS leaf is next in line. If you just used leaf #42, the state updates to #43.

This creates a massive operational hazard: **State Exhaustion and Reuse.**
If a private key's state is ever reused, the cryptography fails catastrophically. This can happen easily in modern infrastructure through:

* Restoring a server from an old backup (reverting the index).
* Cloning a Virtual Machine.
* Forking a process without properly synchronizing the index counter.
* Load-balancing a single private key across multiple servers.

If an attacker captures two different messages signed by leaf #42, they can forge signatures for that key. Therefore, state updates must be perfectly atomic and written to non-volatile memory before the signature is ever released to the requester.

### Standardized Algorithms

NIST has explicitly standardized two stateful hash-based signature schemes under **SP 800-208**:

* **LMS (Leighton-Micali Signature):** Defined in RFC 8554.
* **XMSS (eXtended Merkle Signature Scheme):** Defined in RFC 8391.

Both have multi-tree variants (HSS and XMSS^MT) which layer trees on top of each other to increase the total number of possible signatures (e.g., up to $2^{60}$).

### Where are they used?

Because managing state is too risky and complex for dynamic, high-volume protocols like TLS or standard PGP messaging, stateful signatures are generally restricted to **Roots of Trust and Code Signing**.

They are heavily deployed in hardware security modules (HSMs) for signing firmware updates, OS bootloaders, and software releases—environments where signing is infrequent, centralized, and highly controlled. For everything else (like mTLS or messaging), you would use stateless post-quantum algorithms like ML-DSA.
