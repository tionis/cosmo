(import jhydro)
(use ./util)
(use ./store)

(defn hash_pub_key "get the hash of a public key" [key] (jhydro/hash/hash 32 key "pub__key"))

(defn gen_keys []
  (let [sign_keys (jhydro/sign/keygen)
        kx_keys (jhydro/kx/keygen)]
        (cache/set "node/sign/secret-key" (sign_keys :secret-key))
        (cache/set "node/sign/public-key" (sign_keys :public-key))
        (cache/set "node/kx/secret-key" (kx_keys :secret-key))
        (cache/set "node/kx/public-key" (kx_keys :public-key))))

#(defn verify_file_command [file]
  # TODO check if commit that last modified the file was signed by a node in the :main group (maybe we can manually specify the allowed signers?)
  # maybe save pubkey at compile time?
  #(def status (git "verify-commit" ((git "log" "-n" "1" "--pretty=format:%H" "--" file) :text)))
  #(os/exit status))

#(defn add_signing_key []
  # TODO add this to init for corret commit signing
  # this is kind of a hack to ensure that cosmo:sync keeps working even when the specified key id in .gitconfig is corrupted
  # I could check if cosmo was already setup to use the correct key, but this command only takes 15 ms on my machine and is much more robust
  #set key (set -l _ssh_key (cat ~/.ssh/id_ed25519.pub | string split " ") && echo $_ssh_key[1..2])
  #cosmo store_set user-signing-key "$key"
 # )
