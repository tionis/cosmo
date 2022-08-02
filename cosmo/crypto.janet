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
  # TODO maybe check if allowed_signes and allowed_keys are signed with local key?
  # maybe save pubkey at compile time?
  #(def status (git "verify-commit" ((git "log" "-n" "1" "--pretty=format:%H" "--" file) :text)))
  #(os/exit status))

#(defn list_unsigned_files []
  # TODO
  # {(deps cosmo:verify_file)}
  #for file in (git ls-files)
  #      if not cosmo:verify_file $file >/dev/null 2>&1
  #          echo $file
  #      end
  # end
  #)

#(defn add_signing_key []
  # TODO
  # this is kind of a hack to ensure that cosmo:sync keeps working even when the specified key id in .gitconfig is corrupted
  # I could check if cosmo was already setup to use the correct key, but this command only takes 15 ms on my machine and is much more robust
  #set key (set -l _ssh_key (cat ~/.ssh/id_ed25519.pub | string split " ") && echo $_ssh_key[1..2])
  #cosmo store_set user-signing-key "$key"
 # )

#(defn secrets_help []
#  (print "secrets allows storing secrets for specific groups of nodes")
#  (print "  encrypt - create and encrypt a secret")
#  (print "  decrypt - decrypt specified secret")
#  (print "  list $OPTIONAL_PATTERN - list secrets and filter with an optional glob-pattern")
#  (print "  encrypt_file - encrypt file")
#  (print "  decrypt_file - decrypt file")
#  (print "  sign_file - sign file")
#  (print "  verify_file - verify file signature")
#  (print "  get_keys_of_group $GROUP - list keys of group")
#  (print "  reencrypt $LIST_OF_GROUPS - reencrypt all secrets of group")
#  (print "  groups - list groups"))

#(defn verify_file [file]
#  (label verified
#    (each line (string/split "\n" (string/trim (slurp (string (home) "/.ssh/allowed_signers"))))
#      (def components (string/split " " line))
#      (def env (os/environ))
#      (def streams (os/pipe))
#      (def f (file/open file))
#      (ev/write (streams 1) (file/read f :all))
#      (file/close f)
#      (def null_stream ((os/pipe) 1))
#      (put env :out null_stream)
#      (put env :in (streams 0))
#      (def exit_code (os/execute ["ssh-keygen"
#                                  "-Y" "verify"
#                                  "-f" (string (home) "/.ssh/allowed_signers")
#                                  "-n" "file"
#                                  "-s" (string file ".sig")
#                                  "-I" (components 0)] :pe env))
#      (ev/close (streams 1))
#      (if (= exit_code 0) (return verified true)))
#    (return verified false)))

#(defn secrets_decrypt_secret [secret] 
#  (let [stat (os/stat (path/join (get_cosmo_config_dir) "secrets" "store" (string secret ".age")))]
#    (if (or (= stat nil) (not (= (stat :mode) :file))) (error "Secret does not exist")))
  # TODO verify_file is broken at the moment skipping it for now
  #(if (not (verify_file (string (home) "/.config/cosmo/secrets/store/" secret ".age"))) (error "No valid signature found! Aborting..."))
#  (os/execute ["age" "-i" (string (home) "/.ssh/id_ed25519") "-d" (path/join (get_cosmo_config_dir) "secrets" "store" (string secret ".age"))] :p))

#(defn secrets_decrypt [args]
  # {(deps age secrets:verify_file)}
#  (match args
#    ["help"] (secrets_help)
#    [secret] (secrets_decrypt_secret secret)
#    _ (secrets_help)))
## (os/execute ["fish" "-c" (string "secrets:decrypt " secret)] :p))

#(defn secrets_encrypt [args]
#  (error "Not implemented yet"))
