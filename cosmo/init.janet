#!/bin/env janet
(import ./glob :export true)
(import ./uuid :export true)
(import ./base64 :export true)
(import ./sync :export true)
(import ./crypto :export true)
(import ./daemon :export true)
(import ./universal-vars :export true)
(import ./store :prefix "" :export true)
(import ./util :prefix "" :export true)

(defn status []
  (git/loud "status"))

(defn init []
  # TODO also set git ssh key for signing here, we could also guard against other possible miconfiguration here
  # TODO always ensure that init can be executed as often as you like without changing outcome (I forgot the correct term for that property)
  (print "Starting initialization of cosmo repo...")
  (print "Starting node init")
  # TODO create dirs in .cosmo when needed like messages (and maybe locks?)
  # TODO if already setup ask if node init (skip asking if skip_node_init true)
  # TODO ask for name for this node and which groups it should belong to
  (var old_node_name (cache/get "node/name"))
  (if (or (not old_node_name) (= old_node_name ""))
      (set old_node_name (exec-slurp ["uname" "-n"])))
  (prin (string "node.name[" old_node_name "]> "))(flush)
  (def node_name (string/trim (file/read stdin :line)))
  (def new_node_name (if (= node_name "") old_node_name node_name))
  (cache/set "node/name" new_node_name)
  #   YES -> print out command: cosmo init_node "$NAME" "$PUB_KEY" $GROUPS
  #   NO  -> print out command: cosmo init_node "$NAME" "$PUB_KEY" $GROUPS
  # This command adds the key of the node to the repo, signs and commits it, reecnrypts secrets which belong the mentioned groups and pushes it
  # At the same time it checks which git hoster is used and depending on the groups its in adds the key to the user keys or the repo deploy keys using the respective api and tokens saved in secrets
  # if command on other trusted machine is finished, the user should confirm this on the new node
  # check if clone is successfull, else tell the user and wait for confirmation to try again, start completly from the beginning or abort the whole init process
  # TODO if no hooks exist yet check if there are some at .config/cosmo/default_hooks and install them by copying them to .cosmo
  (let [source (path/join (get_cosmo_config_dir) "hooks" "pre-sync")
        target (path/join (get-cosmo-dir) "hooks" "pre-sync")]
    (if (file_exists? source)
        (do (spit target (slurp source))
            (os/chmod target "rwx------"))))
  (let [source (path/join (get_cosmo_config_dir) "hooks" "post-sync")
        target (path/join (get-cosmo-dir) "hooks" "post-sync")]
    (if (file_exists? source)
        (do (spit target (slurp source))
            (os/chmod target "rwx------"))))
  # TODO execute script at .config/cosmo/init.janet
  (os/mkdir (string (get-cosmo-dir) "/messages"))
  (git "config" "gpg.ssh.allowedSignersFile" (string (os/getenv "HOME") "/.ssh/allowed_signers"))
  (if (cache/get "node/sign/secret-key")
      (print "Skipping key generation as there are keys saved.")
      (do (prin "Generating and saving machine keys...")
          (crypto/gen_keys)
          (print "  Done.")))
  (print "Finished."))

(defn get_nodes_in_group [group]
  # TODO move groups to .ssh or other non-fish location
  (def path (string (os/getenv "HOME") "/.config/fish/data/groups/" group))
  (if (let [metadata (os/stat path)] (and metadata (= (metadata :mode) :file)))
    (print (string/trim (slurp path)))
    (do (eprint "Group does not exist!")
      (os/exit 1))))

(defn universal_vars/help []
  (print "Universal Vars allow for the use of global environment variables that are loaded at the start of each shell session")
  (print "to use these include something like this in your .bashrc/config.fish etc:")
  (print "eval $(git universal_vars)")
  (print "These are all available universal_vars subcommands:")
  (print "  help - this help")
  (print "  export - allow exporting of the universal vars by evaling the result") # TODO improve explanation
  (print "  set $key $value - set the env var specified by $key to $value")
  (print "  rm $key - delete env var called $key")
  (print "  get $key - get the env var by $key, this is not very efficient, and shell scripts should just use the vars that are normally loaded at shell startup")
  (print "  global set $key $value - set the env var specified by $key to $value globally")
  (print "  global get $key - get the global env var by $key")
  (print "  global rm $key - remove a global env var")
  (print "  global ls - list only global env vars"))

#(defn motd []
#  (def motds (cache/get [:motd]))
#  (if motds
#    (eachk id motds
#      (def data (motds id))
#      (print "Message from " (data :source) " created at <" (data :created_at) "> [" id "]:")
#      (prin "Message: " (data :data))(flush))))

#(defn motd/add [source id]
#  (def input (file/read stdin :all))
#  (cache/set [:motd id] {:source source :data input :created_at (get-iso-datetime)}))

#(defn motd/rm [id]
#  (cache/set [:motd id] nil))
