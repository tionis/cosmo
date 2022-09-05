(use ./util)
(import flock)
(import ./glob)
(import ./base64)
#(import ./crypto)

#### Local Store #####
(defn cache/get [key]
  (def path (path/join (get_cosmo_config_dir) ".git" "cache" (path/join ;(path/posix/parts key))))
  (let [stat (os/stat path)]
    (if (or (= stat nil) (not (= (stat :mode) :file)))
      nil # Key does not exist
      ((parse (slurp path)) :value))))

(defn cache/set [key value]
  (def formatted-key (path/join ;(path/posix/parts key)))
  (def path (path/join (get_cosmo_config_dir) ".git" "cache" formatted-key))
  (if (not value)
    (os/rm (path/join (get_cosmo_config_dir) ".git" "cache" key))
    (do
      (create_dirs_if_not_exists (path/join (get_cosmo_config_dir) ".git" "cache" (path/dirname formatted-key)))
      (spit path (string/format "%p" {:key key :value value})))))

(defn cache/rm [key] (cache/set key nil))

(defn cache/ls [glob-pattern]
  (def store-path (path/join (get_cosmo_config_dir) ".git" "cache"))
  (create_dirs_if_not_exists store-path)
  (def ret @[])
  (def prev (os/cwd))
  (os/cd store-path)
  (if (= glob-pattern nil)
    (sh/scan-directory "." |(array/push ret $0))
    (let [pattern (glob/glob-to-peg glob-pattern)]
        (sh/scan-directory "."
                                   |(if (peg/match pattern $0)
                                        (array/push ret $0)))))
  (os/cd prev)
  ret)

(defn cache/ls-contents [glob-pattern]
  (def ret @{})
  (each item (cache/ls glob-pattern)
    (put ret item (cache/get item)))
  ret)

##### Global Store #####
(defn store/get [key]
  (def path (path/join (get_cosmo_config_dir) "store" (path/join ;(path/posix/parts key))))
  (let [stat (os/stat path)]
    (if (or (= stat nil) (not (= (stat :mode) :file)))
      nil # Key does not exist
      ((parse (slurp path)) :value))))
  # TODO verify signature with by using (string/split "\n") 0 is the jdn with the :author (which is a node-id), the :value.
  # :key is the relative path/key, during checking signature also check that :name matches relative path
  # if value is encrypted then :groups specifies the target groups, else it is omitted
  # the second value is the base64 encoded signature)

(defn store/set [key value] # TODO add encryption by specifying recipients
  (def formatted-key (path/join ;(path/posix/parts key)))
  (def path (path/join (get_cosmo_config_dir) "store" formatted-key))
  (if (not value)
    (do
      (def path (path/join (get_cosmo_config_dir) "store" key))
      (with [sync_lock (get-sync-lock)]
      (os/rm path)
      (git/loud_fail_on_error "reset")
      (git/loud_fail_on_error "add" "-f" path)
      (git/loud_fail_on_error "commit" "-m" (string "store: deleted " key))
      (flock/release sync_lock)))
    (do
      (create_dirs_if_not_exists (path/join (get_cosmo_config_dir) "store" (path/dirname formatted-key)))
      (def node-id (base64/encode (cache/get "node/sign/public-key")))
      (if (or (not node-id) (= node-id "")) (error "Could not read node-id from local store/cache"))
      (spit path (string/format "%p" {:key key :value value :author node-id}))
      # TODO if encrypted generate key and encrypt it for each possible recipient
      # -> save encrypted value in :value
      # -> save keys like this: {:keys ["pub-key" "encrypted-key"]}
      # also save groups in :groups
      # TODO generate signature
      (with [sync_lock (get-sync-lock)]
        (git/loud_fail_on_error "reset")
        (git/loud_fail_on_error "add" "-f" path)
        (git/loud_fail_on_error "commit" "-m" (string "store: set " key " to " value)))))) # INFO this will output things <struct 0x5650D46E7DE8> for complex datatypes but that should be ok

(defn store/ls [glob-pattern]
  (def store-path (path/join (get_cosmo_config_dir) "store"))
  (create_dirs_if_not_exists store-path)
  (def ret @[])
  (def prev (os/cwd))
  (os/cd store-path)
  (if (= glob-pattern nil)
    (sh/scan-directory "." |(array/push ret $0))
    (let [pattern (glob/glob-to-peg glob-pattern)]
        (sh/scan-directory "."
                                   |(if (peg/match pattern $0)
                                        (array/push ret $0)))))
  (os/cd prev)
  ret)

(defn store/rm [key] (store/set key nil))

(defn store/ls-contents [glob-pattern]
  (def ret @{})
  (each item (store/ls glob-pattern)
    (put ret item (store/get item)))
  ret)
