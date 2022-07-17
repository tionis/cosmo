#!/bin/env janet
(use spork)
(import flock)
(import ./glob)
(import ./uuid)
(import jhydro)
(import sqlite3)
(import ./base64)

(defn home []
  (os/getenv "HOME"))

(defn get_cfg_dir []
  (string (home) "/.cfg"))

(defn to_two_digit_string [num]
  (if (< num 9)
    (string "0" num)
    (string num)))

(defn get-iso-datetime []
  (def date (os/date))
  (string (date :year) "-" (to_two_digit_string (date :month)) "-" (to_two_digit_string (date :month-day))
          "T"
          (to_two_digit_string (date :hours)) ":" (to_two_digit_string (date :minutes)) ":" (to_two_digit_string (date :seconds))))

(defn exec_get_string_and_exit_code [args]
  (def env (os/environ))
  (def streams (os/pipe))
  (put env :out (streams 1))
  (def proc (os/spawn args :pe env))
  (ev/close (streams 1))
  (def text (string/trim (ev/read (streams 0) :all)))
  (def exit_code (os/proc-wait proc))
  {:exit_code exit_code :text text})

(defn exec_get_string [args] ((exec_get_string args) :text))

(defn hash_pub_key "get the hash of a public key" [key] (jhydro/hash/hash 32 key "pub__key"))

# alternative implementation
(defn shell-out
  "Shell out command and return output"
  [cmd]
  (let [x (os/spawn cmd :p {:out :pipe})
        s (:read (x :out) :all)]
    (:wait x)
    s))

(defn create_dir_if_not_exists [dir]
  (let [meta (os/stat dir)]
    (if (not (and meta (= (meta :mode) :directory)))
      (os/mkdir dir))))

(defn check_git_install []
  (def streams (os/pipe))
  (try (os/execute ["git" "version"] :pe {:out (streams 0)})
    ([_err] false))
  (ev/close (streams 1))
  # TODO check version here
  #(def version (string (ev/read (streams 0) :all)))
  true)

(defn check_age_install []
  (def streams (os/pipe))
  (try (os/execute ["age" "--version"] :pe {:out (streams 0)})
    ([_err] false))
  (ev/close (streams 1))
  # TODO check version here?
  #(def version (string (ev/read (streams 0) :all)))
  true)

(defn get_config_path [] (string (get_cfg_dir) "/config.jdn"))

(defn get_cache_path [] (string (get_cfg_dir) "/cache.jdn"))

(defn file_exists? [path]
  (def stat (os/stat path))
  (and (not (= stat nil)) (= (stat :mode) :file)))

(defn config/get
  "returns a config table"
  []
  (def file_path (get_config_path))
  (if (and (file_exists? file_path) (not (= ((os/stat file_path) :size) 0)))
      (let [config (parse (slurp file_path))]
        (if (not (= (type config) :table)) @{} config))
      @{}))

(defn config/eval
  "modify the config using the given function"
  [func]
  (def file_path (get_config_path))
  (def lock (flock/acquire file_path :block :exclusive))
  (def old_conf (config/get))
  (def new_conf (func old_conf))
  (spit file_path (string/format "%j" new_conf))
  (flock/release lock)
  new_conf)

(defn config/set
  [key-tuple value]
  (config/eval (fn [x] (put-in x key-tuple value) x)))

(defn cache/get
  "returns the cache table"
  [&opt key-tuple]
  (def file_path (get_cache_path))
  (if (and (file_exists? file_path) (not (= ((os/stat file_path) :size) 0)))
      (let [cache (parse (slurp file_path))]
        (if (not (= (type cache) :table))
            @{}
            (if key-tuple
                (get-in cache key-tuple)
                cache)))
      @{}))

(defn cache/eval
  "modify the config using the given function"
  [func]
  (def file_path (get_cache_path))
  (def lock (flock/acquire file_path :block :exclusive))
  (def old_cache (cache/get))
  (def new_cache (func old_cache))
  (spit file_path (string/format "%j" new_cache))
  (flock/release lock)
  new_cache)

(defn cache/set
  [key-tuple value]
  (cache/eval (fn [x] (put-in x key-tuple value) x)))

(defn cfg [& args]
  (def streams (os/pipe))
  (def status (os/execute ["git"
                           (string "--git-dir=" (get_cfg_dir))
                           (string "--work-tree=" (os/getenv "HOME"))
                           ;args]
                          :pe {:out (streams 1) "MERGE_AUTOSTASH" "true"}))
  (ev/close (streams 1))
  {:status status :text (string/trim (string (ev/read (streams 0) :all)))})

(defn cfg_fail_on_error [& args]
  (def result (cfg ;args))
  (if (not (= (result :status) 0))
    (error (result :text))
    result))

(defn cfg_loud [& args]
  (os/execute ["git" 
               (string "--git-dir=" (get_cfg_dir))
               (string "--work-tree=" (os/getenv "HOME"))
               ;args] :p))

(defn cfg_loud_fail_on_error [& args]
  (if (not (= (cfg_loud ;args) 0))
    (error "cfg command failed, see above for logs.")))

(defn get_sync_lock []
  (flock/acquire (string (get_cfg_dir) "/sync.lock") :block :exclusive))

(defn sync_enabled? [] # Note: this could be cached in the future
  (def config (config/get))
  (if (config :sync)
    (not ((config :sync) :disabled))
    true))

(defn print_sync_enabled? []
  (if (sync_enabled?)
    (print "Sync enabled!")
    (do (print "Sync disabled!")
      (os/exit 1))))

(defn execute_pre_sync_hook []
  (def path (string (get_cfg_dir) "/hooks/pre-sync.janet"))
  (if (file_exists? path)
    (do (print "Executing pre-sync-hook...")
      ((get-in (dofile path) ['pre-sync :value])))
    true))

(defn execute_post_sync_hook []
  (def path (string (get_cfg_dir) "/hooks/post-sync.janet"))
  (if (file_exists? path)
    (do (print "Executing post-sync-hook...")
      ((get-in (dofile path {:env (curenv)}) ['post-sync :value])))))

(defn sync_after_lock []
  # define some way for hooks that lead to recompilations etc when the incoming changes modify a source-file e.g.
  # $HOME/.config/janet/src/cfg/cfg.janet
  (def head_before_sync ((cfg_fail_on_error "rev-parse" "HEAD") :text))
  (cfg_loud "pull" "--no-rebase" "--no-edit")
  # check if all commits since head_before_sync were signed, abort if not NOTE: this may be to radical and break things, maybe just define that the last edit of some important files should be signed
  # secrets_generate-allowed-signers # TODO only do this when there were relevant changes
  # secrets_generate-allowed-keys # TODO only do this when there were relevant changes
  # cfg:ensure_key-added (can probably be scrapped with a conditional error detection or assumed to be taken care of during init)
  #if type -q systemctl
  #if cfg:changed $HEAD_BEFORE_SYNC $__fish_config_dir/data/services/$NODE_NAME
  #    system:services:setup
  #end
  #end
  #cfg add -A (still needed?)
  (if (not (= ((cfg "rev-parse" "origin") :text) ((cfg "rev-parse" "main") :text)))
    (do (print "Starting push...")
      (cfg_loud "push"))
    (print "Nothing to push"))
  (execute_post_sync_hook))

(defn sync []
  # TODO check if internet and abort if not (this has to be able to be disabled )(maybe check config?)
  (if (sync_enabled?)
    (do
      (try (do (prin "Acquiring sync lock... ")(flush)
             (def sync_lock (get_sync_lock))
             (print "Done.")
             (if (not (execute_pre_sync_hook))
               (do (print "Sync aborted due to pre-sync hook")
                 (os/exit 1)))
             (sync_after_lock)
             (flock/release sync_lock))
        ([err]
          (pp err)
          (print "Normal file locking failed, falling back to using flock...")
          (os/execute ["flock" "-x" (string (get_cfg_dir) "/sync.lock") "-c" "janet -e '(import cfg)(cfg/sync_after_lock)'"] :p))))
    (eprint "Sync disabled!")))

(defn enable_sync [] (config/set [:sync :disabled] nil))

(defn disable_sync [] (config/set [:sync :disabled] true))

(defn sync_status []
  (if (sync_enabled?)
    (os/exit 0)
    (os/exit 1)))

(defn sync_notes []
  # TODO fix this
  (cfg_loud "fetch" "origin" "refs/notes/*:refs/notes/*")
  (cfg_loud "push" "origin" "'refs/notes/*"))

(defn verify_file_command [file]
  # TODO maybe check if allowed_signes and allowed_keys are signed with local key?
  # maybe save pubkey at compile time?
  (def status (cfg "verify-commit" ((cfg "log" "-n" "1" "--pretty=format:%H" "--" file) :text)))
  (os/exit status))

(defn list_unsigned_files []
  # TODO
  # {(deps cfg cfg:verify_file)}
  #for file in (cfg ls-files)
  #      if not cfg:verify_file $file >/dev/null 2>&1
  #          echo $file
  #      end
  # end
  )

(defn add_signing_key []
  # TODO
  # this is kind of a hack to ensure that cfg:sync keeps working even when the specified key id in .gitconfig is corrupted
  # I could check if cfg was already setup to use the correct key, but this command only takes 15 ms on my machine and is much more robust
  #set key (set -l _ssh_key (cat ~/.ssh/id_ed25519.pub | string split " ") && echo $_ssh_key[1..2])
  #cfg store_set user-signing-key "$key"
  )

(defn changed [commit_hash file_path]
  "return 0 when the file at file_path has changed since commit_hash'"
  # TODO  
  #set file_path (string replace $HOME/ '' $file_path)
  #set files_changed (cfg diff --name-only $hash..HEAD)

  #for file in $files_changed
  #if test $file = $file_path
  #return 0
  #end
  #end
  #return 1
  )

(defn store_help []
  (print "Store allows storing unencrypted strings in the cfg git repo, available commands are:")
  (print " get $KEY - Prints the value for key without extra newline")
  (print " set $KEY $VALUE - Set a key to the given value")
  (print " list $OPTIONAL_PATTERN - If glob-pattern was given, list all keys matching it, else list all")
  (print " delete $KEY - Delete the key"))

(defn store_get [key]
  (def path (string (os/getenv "HOME") "/.config/cfg_store/" key))
  (def stat (os/stat path))
  (if (or (= stat nil) (not (= (stat :mode) :file)))
    (do
      (eprint "Key does not exist!")
      (os/exit 1)))
  (prin (slurp path))(flush))

(defn store_set [key value]
  (create_dir_if_not_exists (string (os/getenv "HOME") "/.config/cfg_store"))
  (def path (string (os/getenv "HOME") "/.config/cfg_store/" key))
  (spit path value)
  (def sync_lock (get_sync_lock))
  (cfg_loud_fail_on_error "reset")
  (cfg_loud_fail_on_error "add" "-f" path)
  (cfg_loud_fail_on_error "commit" "-m" (string "store: set " key " to " value))
  (flock/release sync_lock))

(defn store_list [glob-pattern]
  (create_dir_if_not_exists (string (os/getenv "HOME") "/.config/cfg_store"))
  (if (= glob-pattern nil)
    (each file (os/dir (string (os/getenv "HOME") "/.config/cfg_store"))
      (print file))
    (do (def pattern (glob/glob-to-peg glob-pattern))
      (each file (os/dir (string (os/getenv "HOME") "/.config/cfg_store"))
        (if (peg/match pattern file) (print file))))))

(defn store_delete [key]
  (def path (string (os/getenv "HOME") "/.config/cfg_store/" key))
  (def sync_lock (get_sync_lock))
  (os/rm path)
  (cfg_loud_fail_on_error "reset")
  (cfg_loud_fail_on_error "add" "-f" path)
  (cfg_loud_fail_on_error "commit" "-m" (string "store: deleted " key))
  (flock/release sync_lock))

(defn secrets_help []
  (print "secrets allows storing secrets for specific groups of nodes")
  (print "  encrypt - create and encrypt a secret")
  (print "  decrypt - decrypt specified secret")
  (print "  list $OPTIONAL_PATTERN - list secrets and filter with an optional glob-pattern")
  (print "  encrypt_file - encrypt file")
  (print "  decrypt_file - decrypt file")
  (print "  sign_file - sign file")
  (print "  verify_file - verify file signature")
  (print "  get_keys_of_group $GROUP - list keys of group")
  (print "  reencrypt $LIST_OF_GROUPS - reencrypt all secrets of group")
  (print "  groups - list groups"))

(defn verify_file [file]
  (label verified
    (each line (string/split "\n" (string/trim (slurp (string (home) "/.ssh/allowed_signers"))))
      (def components (string/split " " line))
      (def env (os/environ))
      (def streams (os/pipe))
      (def f (file/open file))
      (ev/write (streams 1) (file/read f :all))
      (file/close f)
      (def null_stream ((os/pipe) 1))
      (put env :out null_stream)
      (put env :in (streams 0))
      (def exit_code (os/execute ["ssh-keygen"
                                  "-Y" "verify"
                                  "-f" (string (home) "/.ssh/allowed_signers")
                                  "-n" "file"
                                  "-s" (string file ".sig")
                                  "-I" (components 0)] :pe env))
      (ev/close (streams 1))
      (if (= exit_code 0) (return verified true)))
    (return verified false)))

(defn secrets_decrypt_secret [secret] 
  (let [stat (os/stat (string (home) "/.config/cfg/secrets/store/" secret ".age"))]
    (if (or (= stat nil) (not (= (stat :mode) :file))) (error "Secret does not exist")))
  # TODO verify_file is broken at the moment skipping it for now
  #(if (not (verify_file (string (home) "/.config/cfg/secrets/store/" secret ".age"))) (error "No valid signature found! Aborting..."))
  (os/execute ["age" "-i" (string (home) "/.ssh/id_ed25519") "-d" (string (home) "/.config/cfg/secrets/store/" secret ".age")] :p))

(defn secrets_decrypt [args]
  # {(deps age secrets:verify_file)}
  (match args
    ["help"] (secrets_help)
    [secret] (secrets_decrypt_secret secret)
    _ (secrets_help)))
# (os/execute ["fish" "-c" (string "secrets:decrypt " secret)] :p))

(defn secrets_encrypt [args]
  (error "Not implemented yet"))

(defn status []
  (cfg_loud "status"))

(defn init []
  # TODO also set git ssh key for signing here, we could also guard against other possible miconfiguration here
  # TODO always ensure that init can be executed as often as you like without changing outcome (I forgot the correct term for that property)
  (print "Starting initialization of cfg repo...")
  (print "Starting node init")
  # TODO create dirs in .cfg when needed like messages (and maybe locks?)
  #TODO if already setup ask if node init (skip asking if skip_node_init true)
  #TODO ask for name for this node and which groups it should belong to
  (def config (config/get))
  (var old_node_name (get-in config [:node :name]))
  (if (= old_node_name "") (set old_node_name (exec_get_string ["uname" "-n"])))
  (prin (string "node.name[" old_node_name "]> "))(flush)
  (def node_name (string/trim (file/read stdin :line)))
  (def new_node_name (if (= node_name "") old_node_name node_name))
  (config/set [:node :name] new_node_name)
  #   YES -> print out command: cfg init_node "$NAME" "$PUB_KEY" $GROUPS
  #   NO  -> print out command: cfg init_node "$NAME" "$PUB_KEY" $GROUPS
  # This command adds the key of the node to the repo, signs and commits it, reecnrypts secrets which belong the mentioned groups and pushes it
  # At the same time it checks which git hoster is used and depending on the groups its in adds the key to the user keys or the repo deploy keys using the respective api and tokens saved in secrets
  # if command on other trusted machine is finished, the user should confirm this on the new node
  # check if clone is successfull, else tell the user and wait for confirmation to try again, start completly from the beginning or abort the whole init process
  # TODO if no hooks exist yet check if there are some at .config/cfg/default_hooks and install them by copying them to .cfg
  (let [path (string (home) "/.config/cfg/hooks/pre-sync.janet")]
    (if (file_exists? path)
      (spit (string (get_cfg_dir) "/hooks/pre-sync.janet") (slurp path))))
  (let [path (string (home) "/.config/cfg/hooks/post-sync.janet")]
    (if (file_exists? path)
      (spit (string (get_cfg_dir) "/hooks/post-sync.janet") (slurp path))))
  # TODO execute script at .config/cfg/init.janet
  (os/mkdir (string (get_cfg_dir) "/messages"))
  (cfg "config" "gpg.ssh.allowedSignersFile" (string (os/getenv "HOME") "/.ssh/allowed_signers"))
  (if (get-in config [:node :sign :secret-key])
    (print "Skipping signing key generation as there are keys saved.")
    (do (prin "Generating and saving machine signing keys...")
        (def sign_keys (jhydro/sign/keygen))
        (config/set [:node :sign :secret-key] (sign_keys :secret-key))
        (config/set [:node :sign :public-key] (sign_keys :public-key))
        (print "  Done.")))
  (if (get-in config [:node :kx :secret-key])
      (print "Skipping kx key generation as there are keys saved.")
      (do (prin "Generating and saving machine kx keys...")
          (def kx_keys (jhydro/kx/keygen))
          (config/set [:node :kx :secret-key] (kx_keys :secret-key))
          (config/set [:node :kx :public-key] (kx_keys :public-key))
          (print "  Done.")))
  (print "Finished."))

(defn get_prompt []
  (def sync_status (if (sync_enabled?) "" "sync:disabled "))
  (def changes_array (string/split "\n" ((cfg "status" "--porcelain=v1") :text)))
  (var changes_count (length changes_array))
  (if (= changes_count 1) (if (= (changes_array 0) "") (set changes_count 0)))
  (def changes_status (if (> changes_count 0) (string changes_count " uncommitted changes ")))
  (prin "\x1b[31m" sync_status changes_status "\x1b[37m")(flush))

(defn get_nodes_in_group [group]
  # TODO move groups to .ssh or other non-fish location
  (def path (string (os/getenv "HOME") "/.config/fish/data/groups/" group))
  (if (let [metadata (os/stat path)] (and metadata (= (metadata :mode) :file)))
    (print (string/trim (slurp path)))
    (do (eprint "Group does not exist!")
      (os/exit 1))))

(defn help []
  (print "Top-Level commands for cfg.janet:")
  (print "  help - this help message")
  (print "  get_prompt - returns shell prompt module text")
  (print "  init - intialize a new node")
  (print "  sync - sync commands, for help use cfg sync help")
  (print "  universal_vars - Universal Variables, check cfg universal_vars help")
  (print "  list_unsigned_files - list all files that were last modified in a unsigned commit")
  (print "  verify_file - check if last modification of file was signed")
  (print "  store - store commands, for help use cfg store help")
  (print "  secrets - secrets commands, for help use cfg secrets help")
  (print "  get_nodes_in_group - get nodes in group"))

(defn universal_vars/help []
  (print "Universal Vars allow for the use of global environment variables that are loaded at the start of each shell session")
  (print "to use these include something like this in your .bashrc/config.fish etc:")
  (print "eval $(cfg universal_vars)")
  (print "These are all available universal_vars subcommands:")
  (print "  help - this help")
  (print "  set $key $value - set the env var specified by $key to $value")
  (print "  del $key - delete env var called $key")
  (print "  get $key - get the env var by $key, this is not very efficient, and shell scripts should just use the vars that are normally loaded at shell startup"))

(defn universal_vars/export
  "returns the universal vars formatted for shell consumption"
  []
  (def file_path (path/join (get_cfg_dir) "universal_vars.jdn"))
  (def vars (if (file_exists? file_path)
                (parse (slurp file_path))
                @{}))
  (def config (config/get))
  (eachk key vars
    (print "export " key "=" (vars key)))
  (if (config :node)
      (if ((config :node) :name)
          (print "export NODE_NAME=" ((config :node) :name))
          (print "export NODE_NAME=unknown"))
      (print "export NODE_NAME=unknown")))

(defn universal_vars/get_all []
  (def file_path (path/join (get_cfg_dir) "universal_vars.jdn"))
  (if (and (file_exists? file_path) (not (= ((os/stat file_path) :size) 0)))
      (parse (slurp file_path))
      @{}))

(defn universal_vars/set
  "modify the config using the given function"
  [key value]
  (def file_path (path/join (get_cfg_dir) "universal_vars.jdn"))
  (def lock (flock/acquire file_path :block :exclusive))
  (def old_conf (universal_vars/get_all))
  (def new_conf (put old_conf key value))
  (spit file_path (string/format "%j" new_conf))
  (flock/release lock)
  new_conf)

(defn universal_vars/get
  [key]
  ((universal_vars/get_all) key))

(defn motd []
  (def motds (cache/get [:motd]))
  (if motds
    (eachk id motds
      (def data (motds id))
      (print "Message from " (data :source) " created at <" (data :created_at) "> [" id "]:")
      (prin "Message: " (data :data))(flush))))

(defn motd/add [source id]
  (def input (file/read stdin :all))
  (cache/set [:motd id] {:source source :data input :created_at (get-iso-datetime)}))

(defn motd/rm [id]
  (cache/set [:motd id] nil))

(defn print_id []
  (def config (config/get))
  (print (base64/encode (get-in config [:node :sign :public-key]))))

(defn print_short_id []
  (def config (config/get))
  (print (slice (base64/encode (get-in config [:node :sign :public-key])) 0 4)))

(defn daemon_after_lock []
  # TODO start multiple parallel loops here
  # one that runs every x minutes where x is (/ 1 sync_pulse_frequency) where sync_pulse_frquency is loaded from git config and defaults to .2
  # -> add job check to sync
  # start main supervisor which starts the sub supervisors for the registered services
  # TODO find a way to run janet code dynamically in a sandbox or smth like that
  (forever
    (sync)
    (os/sleep 300)))

(defn daemon/help []
  (print `the cfgd daemon runs in the background to regularily initiate a sync operation
          and also allows some more functionality to be developed
          cfgd subcommands:
            start - start the daemon
            stop - stop the daemon`))

(defn daemon/stop []
  (error "Not implemented"))

(defn daemon/start []
  (try (do (def sync_lock (flock/acquire (string (get_cfg_dir) "/daemon.lock") :noblock :exclusive))
         (if (= sync_lock nil)
           (do (print "Daemon already running!")
             (os/exit 1))
           (print "Started daemon."))
         (daemon_after_lock)
         (flock/release sync_lock))
    ([err]
      (pp err)
      (print "Normal file locking failed, falling back to using flock...")
      (os/execute ["flock" "-x" "-n" (string (get_cfg_dir) "/sync.lock") "-c" "janet -e '(import cfg)(cfg/daemon_after_lock)'"] :p))))

(defn get_node_name []
  (def config (config/get))
  (print ((config :node) :name)))

(defn main [_ & raw_args]
  (match raw_args
    ["init"] (init)
    ["help"] (help)
    ["get_prompt"] (get_prompt)
    ["id"] (print_id)
    ["short-id"] (print_short_id)
    ["s"] (status)
    ["se"] (enable_sync)
    ["sd"] (disable_sync)
    ["ss"] (print_sync_enabled?)
    ["cfg" "eval" func] (pp (config/eval (eval-string func)))
    ["cfg"] (pp (config/get))
    ["store" "help"] (store_help)
    ["store" "get" key] (store_get key)
    ["store" "set" key value] (store_set key value)
    ["store" "list" pattern] (store_list pattern)
    ["store" "list"] (store_list nil)
    ["store" "delete" key] (store_delete key)
    ["store" _] (store_help)
    ["store"] (store_help)
    ["sync" "enabled"] (sync_status)
    ["sync" "status"] (print_sync_enabled?)
    ["sync" "enable"] (enable_sync)
    ["sync" "disable"] (disable_sync)
    ["sync_notes"] (sync_notes)
    ["sync"] (sync)
    ["daemon" "start"] (daemon/start)
    ["daemon" "stop"] (daemon/stop)
    ["daemon" "help"] (daemon/help)
    ["daemon"] (daemon/help)
    ["motd" "add" source id] (motd/add source id)
    ["motd" "add" source] (motd/add source (uuid/new))
    ["motd" "add"] (motd/add "unknown" (uuid/new))
    ["motd" "rm" id] (motd/rm id)
    ["motd"] (motd)
    ["get_node_name"] (get_node_name)
    ["secrets" "help"] (secrets_help)
    ["secrets" "decrypt" & args] (secrets_decrypt args)
    ["secrets" "encrypt" & args] (secrets_encrypt args)
    ["secrets"] (secrets_help)
    ["universal_vars" "help"] (universal_vars/help)
    ["universal_vars" "set" key value] (universal_vars/set key value)
    ["universal_vars" "get" key] (universal_vars/get key)
    ["universal_vars" "del" key] (universal_vars/set key nil)
    ["universal_vars"] (universal_vars/export)
    ["verify_file" file] (verify_file_command file)
    ["list_unsigned_files"] (list_unsigned_files)
    ["get_nodes_in_group" group] (get_nodes_in_group group) # TODO think of better name and change it everywhere
    _ (os/exit (cfg_loud ;raw_args))))
